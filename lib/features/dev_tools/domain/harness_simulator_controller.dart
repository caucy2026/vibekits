import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'simulator_update_service.dart';

import 'rustdesk_harness_share_service.dart';

final class HarnessSimulatorControllerException implements Exception {
  const HarnessSimulatorControllerException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

abstract interface class HarnessSimulatorMcpClient {
  Future<List<Map<String, Object?>>> initializeAndList(
    int localPort, {
    String callerId = '',
  });

  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments, {
    String callerId = '',
  });
}

final class _LoopbackHarnessSimulatorMcpClient
    implements HarnessSimulatorMcpClient {
  const _LoopbackHarnessSimulatorMcpClient();

  static const String _protocolVersion = '2025-06-18';
  static const int _maxResponseBytes = 1024 * 1024;

  @override
  Future<List<Map<String, Object?>>> initializeAndList(
    int localPort, {
    String callerId = '',
  }) async {
    final initialized = await _rpc(
      localPort,
      1,
      'initialize',
      <String, Object?>{
        'protocolVersion': _protocolVersion,
        'capabilities': const <String, Object?>{},
        'clientInfo': const <String, Object?>{
          'name': 'VibeKits ID Simulator Controller',
          'version': '1',
        },
      },
      callerId: callerId,
    );
    if (initialized['protocolVersion'] != _protocolVersion) {
      throw const HarnessSimulatorControllerException(
        'incompatible_protocol',
        '远端仿真机 MCP 协议不兼容',
      );
    }
    await _notification(
      localPort,
      'notifications/initialized',
      callerId: callerId,
    );
    final result = await _rpc(
      localPort,
      2,
      'tools/list',
      const <String, Object?>{},
      callerId: callerId,
    );
    final raw = result['tools'];
    if (raw is! List) {
      throw const HarnessSimulatorControllerException(
        'invalid_catalog',
        '远端仿真机没有返回工具目录',
      );
    }
    final tools = <Map<String, Object?>>[];
    final names = <String>{};
    for (final item in raw) {
      if (item is! Map) {
        throw const HarnessSimulatorControllerException(
          'invalid_catalog',
          '远端仿真机工具目录格式错误',
        );
      }
      final tool = Map<String, Object?>.from(item);
      final name = '${tool['name'] ?? ''}'.trim();
      if (name.isEmpty || !names.add(name)) {
        throw const HarnessSimulatorControllerException(
          'invalid_catalog',
          '远端仿真机工具名称为空或重复',
        );
      }
      tools.add(tool);
    }
    return List<Map<String, Object?>>.unmodifiable(tools);
  }

  @override
  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments, {
    String callerId = '',
  }) => _rpc(
    localPort,
    3,
    'tools/call',
    <String, Object?>{'name': toolId, 'arguments': arguments},
    callerId: callerId,
    timeout: toolId == 'vibekits.device.ssh_authorize'
        ? const Duration(minutes: 2)
        : const Duration(seconds: 8),
  );

  Future<Map<String, Object?>> _rpc(
    int port,
    int id,
    String method,
    Map<String, Object?> params, {
    String callerId = '',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    late final Map<String, Object?> response;
    try {
      response = await _post(port, <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }, callerId: callerId, timeout: timeout);
    } on HarnessSimulatorControllerException catch (error) {
      throw HarnessSimulatorControllerException(
        error.code,
        '${error.message}（阶段：$method）',
      );
    }
    if (response['jsonrpc'] != '2.0' || response['id'] != id) {
      throw const HarnessSimulatorControllerException(
        'invalid_response',
        '远端仿真机响应身份不匹配',
      );
    }
    final error = response['error'];
    if (error != null) {
      final message = error is Map ? '${error['message'] ?? error}' : '$error';
      throw HarnessSimulatorControllerException('remote_error', message);
    }
    final result = response['result'];
    if (result is! Map) {
      throw const HarnessSimulatorControllerException(
        'invalid_response',
        '远端仿真机响应缺少结果',
      );
    }
    return Map<String, Object?>.from(result);
  }

  Future<void> _notification(
    int port,
    String method, {
    String callerId = '',
  }) async {
    try {
      await _post(port, <String, Object?>{
        'jsonrpc': '2.0',
        'method': method,
        'params': const <String, Object?>{},
      }, callerId: callerId);
    } on HarnessSimulatorControllerException catch (error) {
      throw HarnessSimulatorControllerException(
        error.code,
        '${error.message}（阶段：$method）',
      );
    }
  }

  Future<Map<String, Object?>> _post(
    int port,
    Map<String, Object?> payload, {
    String callerId = '',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port/mcp'))
          .timeout(timeout);
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('MCP-Protocol-Version', _protocolVersion);
      if (callerId.trim().isNotEmpty) {
        request.headers.set('x-vibekits-caller-id', callerId.trim());
      }
      final bytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > _maxResponseBytes) {
          throw const HarnessSimulatorControllerException(
            'response_too_large',
            '远端仿真机响应超过 1 MiB',
          );
        }
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.accepted) {
        final code = response.statusCode == HttpStatus.forbidden
            ? 'remote_disabled'
            : 'http_${response.statusCode}';
        throw HarnessSimulatorControllerException(
          code,
          '远端仿真机 HTTP 状态 ${response.statusCode}',
        );
      }
      if (builder.length == 0) return const <String, Object?>{};
      final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
      if (decoded is! Map) {
        throw const HarnessSimulatorControllerException(
          'invalid_response',
          '远端仿真机返回了无效 JSON',
        );
      }
      return Map<String, Object?>.from(decoded);
    } on TimeoutException {
      throw const HarnessSimulatorControllerException(
        'mcp_timeout',
        '远端仿真机 MCP 响应超时',
      );
    } on SocketException catch (error) {
      throw HarnessSimulatorControllerException(
        'mcp_unreachable',
        '远端仿真机 MCP 不可达：${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef HarnessSimulatorHostResolver = Future<RustDeskHostInfo> Function();
typedef HarnessSimulatorTunnelOpener =
    Future<RustDeskHarnessTunnelLease> Function(
      String executable,
      String routingId,
      int localPort,
      bool forceRelay,
    );
typedef HarnessSimulatorPortAllocator = Future<int> Function();
typedef HarnessSimulatorSshTunnelOpener =
    Future<RustDeskHarnessTunnelLease> Function(
      String executable,
      String routingId,
      int localPort,
      bool forceRelay,
    );
typedef HarnessSimulatorProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Controller-side ID-only simulator session registry.
///
/// Callers provide only a VibeKits routing ID. Ports, direct/relay selection
/// and loopback MCP transport remain implementation details and are never
/// exposed as user configuration.
final class HarnessSimulatorController {
  HarnessSimulatorController({
    HarnessSimulatorHostResolver? resolveHost,
    HarnessSimulatorTunnelOpener? openTunnel,
    HarnessSimulatorPortAllocator? allocatePort,
    HarnessSimulatorMcpClient? mcpClient,
    HarnessSimulatorSshTunnelOpener? openSshTunnel,
    HarnessSimulatorProcessRunner? processRunner,
    Directory? sshKeyRoot,
    this.enableSshBootstrap = true,
  }) : _resolveHost =
           resolveHost ?? RustDeskHarnessShareService.ensureHostAvailable,
       _openTunnel = openTunnel ?? _defaultOpenTunnel,
       _allocatePort =
           allocatePort ?? RustDeskHarnessShareService.allocateTunnelPort,
       _mcpClient = mcpClient ?? const _LoopbackHarnessSimulatorMcpClient(),
       _openSshTunnel = openSshTunnel ?? _defaultOpenSshTunnel,
       _processRunner = processRunner ?? Process.run,
       _sshKeyRootOverride = sshKeyRoot;

  static final HarnessSimulatorController shared = HarnessSimulatorController();

  final HarnessSimulatorHostResolver _resolveHost;
  final HarnessSimulatorTunnelOpener _openTunnel;
  final HarnessSimulatorPortAllocator _allocatePort;
  final HarnessSimulatorMcpClient _mcpClient;
  final HarnessSimulatorSshTunnelOpener _openSshTunnel;
  final HarnessSimulatorProcessRunner _processRunner;
  final Directory? _sshKeyRootOverride;
  final bool enableSshBootstrap;
  final Map<String, _HarnessSimulatorSession> _sessions =
      <String, _HarnessSimulatorSession>{};
  final StreamController<Map<String, Object?>> _changes =
      StreamController<Map<String, Object?>>.broadcast(sync: true);

  /// Process-local controller state used only to project an outgoing simulator
  /// connection into the shell. Transport ownership remains in this class.
  Stream<Map<String, Object?>> get changes => _changes.stream;

  static Future<RustDeskHarnessTunnelLease> _defaultOpenTunnel(
    String executable,
    String routingId,
    int localPort,
    bool forceRelay,
  ) => RustDeskHarnessShareService.openSimulatorTunnel(
    executable,
    routingId: routingId,
    localPort: localPort,
    forceRelay: forceRelay,
  );

  static Future<RustDeskHarnessTunnelLease> _defaultOpenSshTunnel(
    String executable,
    String routingId,
    int localPort,
    bool forceRelay,
  ) => RustDeskHarnessShareService.openSimulatorSshTunnel(
    executable,
    routingId: routingId,
    localPort: localPort,
    forceRelay: forceRelay,
  );

  Future<Map<String, Object?>> connect(
    String routingId, {
    bool forceRelay = false,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final id = routingId.trim();
    _validateId(id);
    final existing = _sessions[id];
    if (existing != null) return _snapshot(existing);

    final host = await _resolveHost();
    if (!host.available || !host.callable || host.executable.isEmpty) {
      throw HarnessSimulatorControllerException(
        'controller_unavailable',
        host.message.isEmpty ? '本机 ID 通信引擎未就绪' : host.message,
      );
    }
    final localPort = await _allocatePort();
    final tunnel = await _openTunnel(
      host.executable,
      id,
      localPort,
      forceRelay,
    );
    try {
      // The first MCP request is also the demand signal for RustDesk's local
      // port forward. Sending a disposable trigger connection first creates a
      // second handshake and can race the listener; buffer this real request
      // until the single transport is authenticated instead.
      final toolsFuture = _mcpClient
          .initializeAndList(localPort, callerId: host.id)
          .timeout(timeout);
      // Attach an error observer immediately because the target may close the
      // demand TCP request while the native carrier is still reporting the
      // more useful login failure (for example, access explicitly disabled).
      // The original future remains authoritative and is awaited below once
      // transport authentication succeeds.
      unawaited(
        toolsFuture.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {},
        ),
      );
      await tunnel.waitUntilConnected(timeout: timeout);
      final tools = await toolsFuture;
      final ssh = !enableSshBootstrap || Platform.isAndroid || Platform.isIOS
          ? null
          : await _prepareSshSession(
              host: host,
              routingId: id,
              mcpPort: localPort,
              forceRelay: forceRelay,
              tools: tools,
              timeout: timeout,
            );
      final session = _HarnessSimulatorSession(
        routingId: id,
        controllerRoutingId: host.id,
        localPort: localPort,
        forceRelay: forceRelay,
        tunnel: tunnel,
        tools: tools,
        ssh: ssh,
        connectedAt: DateTime.now().toUtc(),
      );
      _sessions[id] = session;
      _publishStatus();
      return _snapshot(session);
    } on Object catch (error) {
      await tunnel.close();
      if (error is HarnessSimulatorControllerException) rethrow;
      final message = '$error';
      final code = message.contains('disabled') || message.contains('forbidden')
          ? 'remote_disabled'
          : message.contains('timeout')
          ? 'target_offline'
          : 'transport_failed';
      throw HarnessSimulatorControllerException(code, message);
    }
  }

  Map<String, Object?> status([String? routingId]) {
    final id = routingId?.trim() ?? '';
    if (id.isNotEmpty) {
      _validateId(id);
      final session = _sessions[id];
      return session == null
          ? <String, Object?>{'connected': false, 'routingId': id}
          : _snapshot(session);
    }
    return <String, Object?>{
      'connected': _sessions.isNotEmpty,
      'sessions': _sessions.values.map(_snapshot).toList(growable: false),
    };
  }

  List<Map<String, Object?>> catalog(String routingId) {
    final session = _requireSession(routingId);
    return session.tools;
  }

  Future<Map<String, Object?>> call(
    String routingId,
    String toolId,
    Map<String, Object?> arguments,
  ) async {
    final session = _requireSession(routingId);
    final name = toolId.trim();
    if (name.isEmpty ||
        !session.tools.any((tool) => '${tool['name'] ?? ''}' == name)) {
      throw const HarnessSimulatorControllerException(
        'unknown_remote_tool',
        '远端仿真机没有公开这个工具',
      );
    }
    return _mcpClient.call(
      session.localPort,
      name,
      arguments,
      callerId: session.controllerRoutingId,
    );
  }

  Future<Map<String, Object?>> runSshCommand(
    String routingId,
    String command, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final session = _requireSession(routingId);
    final ssh = session.ssh;
    if (ssh == null) {
      throw const HarnessSimulatorControllerException(
        'ssh_not_ready',
        '该仿真连接尚未完成 SSH 公钥验证',
      );
    }
    final source = command.trim();
    if (source.isEmpty ||
        source.length > 8192 ||
        source.codeUnits.any((unit) => unit == 0)) {
      throw const FormatException('远程命令为空、过长或包含非法字符');
    }
    final result = await _processRunner(_sshExecutable(), <String>[
      ..._sshOptions(ssh),
      '${ssh.username}@127.0.0.1',
      source,
    ]).timeout(timeout);
    return <String, Object?>{
      'routingId': routingId.trim(),
      'hostname': ssh.hostname,
      'exitCode': result.exitCode,
      'stdout': _boundedOutput('${result.stdout}'),
      'stderr': _boundedOutput('${result.stderr}'),
      'ok': result.exitCode == 0,
    };
  }

  Future<Map<String, Object?>> uploadFile(
    String routingId,
    String localPath,
  ) async {
    final session = _requireSession(routingId);
    final ssh = session.ssh;
    if (ssh == null) {
      throw const HarnessSimulatorControllerException(
        'ssh_not_ready',
        '该仿真连接尚未完成 SSH 公钥验证',
      );
    }
    final source = File(localPath).absolute;
    if (!source.isAbsolute || !await source.exists()) {
      throw const FormatException('上传源必须是存在的绝对文件路径');
    }
    final stat = await source.stat();
    if (stat.size <= 0 || stat.size > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('上传文件大小超出 2 GiB 限制');
    }
    final originalName = source.uri.pathSegments.last;
    final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      throw const FormatException('上传文件名无效');
    }
    final remoteDirectory = '/tmp/vibekits-simulator-${routingId.trim()}';
    final remotePath = '$remoteDirectory/$safeName';
    final prepared = await runSshCommand(
      routingId,
      "mkdir -p '$remoteDirectory' && chmod 700 '$remoteDirectory'",
    );
    if (prepared['ok'] != true) throw StateError('目标机暂存目录准备失败');
    final copied = await _processRunner(_scpExecutable(), <String>[
      ..._scpOptions(ssh),
      source.path,
      '${ssh.username}@127.0.0.1:$remotePath',
    ]).timeout(const Duration(minutes: 15));
    if (copied.exitCode != 0) {
      throw HarnessSimulatorControllerException(
        'sftp_upload_failed',
        '目标机文件上传失败：${copied.stderr}',
      );
    }
    final localSha = (await sha256.bind(source.openRead()).first).toString();
    final verified = await runSshCommand(
      routingId,
      "shasum -a 256 '$remotePath'",
    );
    final remoteSha = RegExp(
      r'\b[0-9a-fA-F]{64}\b',
    ).firstMatch('${verified['stdout'] ?? ''}')?.group(0)?.toLowerCase();
    if (verified['ok'] != true || remoteSha != localSha.toLowerCase()) {
      throw const HarnessSimulatorControllerException(
        'upload_checksum_mismatch',
        '目标机文件 SHA-256 与本机不一致',
      );
    }
    return <String, Object?>{
      'uploaded': true,
      'routingId': routingId.trim(),
      'hostname': ssh.hostname,
      'remotePath': remotePath,
      'bytes': stat.size,
      'sha256': remoteSha,
    };
  }

  static List<String> _sshOptions(_HarnessSimulatorSshSession ssh) => <String>[
    '-o',
    'BatchMode=yes',
    '-o',
    'IdentitiesOnly=yes',
    '-o',
    'StrictHostKeyChecking=yes',
    '-o',
    _knownHostsOption(ssh.knownHostsPath),
    '-o',
    'GlobalKnownHostsFile=/dev/null',
    '-o',
    'KexAlgorithms=curve25519-sha256',
    '-o',
    'HostKeyAlgorithms=ssh-ed25519',
    '-i',
    ssh.privateKeyPath,
    '-p',
    '${ssh.localPort}',
  ];

  static List<String> _scpOptions(_HarnessSimulatorSshSession ssh) => <String>[
    '-q',
    '-o',
    'BatchMode=yes',
    '-o',
    'IdentitiesOnly=yes',
    '-o',
    'StrictHostKeyChecking=yes',
    '-o',
    _knownHostsOption(ssh.knownHostsPath),
    '-o',
    'GlobalKnownHostsFile=/dev/null',
    '-o',
    'KexAlgorithms=curve25519-sha256',
    '-o',
    'HostKeyAlgorithms=ssh-ed25519',
    '-i',
    ssh.privateKeyPath,
    '-P',
    '${ssh.localPort}',
  ];

  static String _boundedOutput(String value) => value.length <= 64 * 1024
      ? value
      : value.substring(value.length - 64 * 1024);

  Future<_HarnessSimulatorSshSession> _prepareSshSession({
    required RustDeskHostInfo host,
    required String routingId,
    required int mcpPort,
    required bool forceRelay,
    required List<Map<String, Object?>> tools,
    required Duration timeout,
  }) async {
    const requiredTools = <String>{
      'vibekits.device.ssh_identity',
      'vibekits.device.ssh_key_status',
      'vibekits.device.ssh_authorize',
    };
    final names = tools.map((tool) => '${tool['name'] ?? ''}').toSet();
    if (!names.containsAll(requiredTools)) {
      throw const HarnessSimulatorControllerException(
        'ssh_bootstrap_unavailable',
        '远端版本不支持自动 SSH 公钥交换，需要先升级目标机 VibeKits',
      );
    }
    final identity = _toolData(
      await _mcpClient.call(
        mcpPort,
        'vibekits.device.ssh_identity',
        const <String, Object?>{},
        callerId: host.id,
      ),
    );
    final username = '${identity['username'] ?? ''}'.trim();
    final fingerprint = '${identity['hostKeyFingerprint'] ?? ''}'.trim();
    if (username.isEmpty || !fingerprint.startsWith('SHA256:')) {
      throw const HarnessSimulatorControllerException(
        'ssh_identity_invalid',
        '远端 SSH 用户或主机指纹无效',
      );
    }
    final keyRoot = await _resolveSshKeyRoot(routingId);
    final privateKey = File('${keyRoot.path}/id_ed25519');
    final publicKey = File('${privateKey.path}.pub');
    if (!await privateKey.exists() || !await publicKey.exists()) {
      final generated = await _processRunner(_sshKeygenExecutable(), <String>[
        '-q',
        '-t',
        'ed25519',
        '-N',
        '',
        '-C',
        'vibekits-simulator-${host.id}',
        '-f',
        privateKey.path,
      ]).timeout(const Duration(seconds: 15));
      if (generated.exitCode != 0) {
        throw HarnessSimulatorControllerException(
          'ssh_key_generation_failed',
          '控制端 SSH 密钥生成失败：${generated.stderr}',
        );
      }
    }
    final publicKeyText = (await publicKey.readAsString()).trim();
    final keyStatus = _toolData(
      await _mcpClient.call(
        mcpPort,
        'vibekits.device.ssh_key_status',
        <String, Object?>{'peerId': host.id, 'publicKey': publicKeyText},
        callerId: host.id,
      ),
    );
    if (keyStatus['authorized'] != true) {
      _toolData(
        await _mcpClient.call(
          mcpPort,
          'vibekits.device.ssh_authorize',
          <String, Object?>{'peerId': host.id, 'publicKey': publicKeyText},
          callerId: host.id,
        ),
      );
    }
    final localPort = await _allocatePort();
    final tunnel = await _openSshTunnel(
      host.executable,
      routingId,
      localPort,
      forceRelay,
    );
    try {
      final knownHosts = File('${keyRoot.path}/known_hosts');
      if (await knownHosts.exists()) await knownHosts.delete();
      final captureFuture = _processRunner(_sshExecutable(), <String>[
        '-o',
        'BatchMode=yes',
        '-o',
        'IdentitiesOnly=yes',
        '-o',
        'StrictHostKeyChecking=accept-new',
        '-o',
        _knownHostsOption(knownHosts.path),
        '-o',
        'GlobalKnownHostsFile=/dev/null',
        '-o',
        'PreferredAuthentications=none',
        '-o',
        'KexAlgorithms=curve25519-sha256',
        '-o',
        'HostKeyAlgorithms=ssh-ed25519',
        '-o',
        'ConnectTimeout=8',
        '-p',
        '$localPort',
        '$username@127.0.0.1',
      ]).timeout(timeout);
      await tunnel.waitUntilConnected(timeout: timeout);
      final ProcessResult captureResult = await captureFuture;
      if (!await knownHosts.exists() || await knownHosts.length() == 0) {
        final String detail = _boundedOutput('${captureResult.stderr}').trim();
        throw StateError(
          '无法读取隧道后的 SSH 主机密钥'
          '（exit=${captureResult.exitCode}'
          '${detail.isEmpty ? '' : '，$detail'}）',
        );
      }
      final scannedFingerprint = await _processRunner(
        _sshKeygenExecutable(),
        <String>['-lf', knownHosts.path, '-E', 'sha256'],
      );
      final actualFingerprint = RegExp(
        r'\b(SHA256:[A-Za-z0-9+/=]+)\b',
      ).firstMatch('${scannedFingerprint.stdout}')?.group(1);
      if (scannedFingerprint.exitCode != 0 ||
          actualFingerprint != fingerprint) {
        throw const HarnessSimulatorControllerException(
          'ssh_host_key_mismatch',
          'SSH 主机指纹与已认证仿真通道返回值不一致',
        );
      }
      final probe = await _processRunner(_sshExecutable(), <String>[
        '-o',
        'BatchMode=yes',
        '-o',
        'IdentitiesOnly=yes',
        '-o',
        'StrictHostKeyChecking=yes',
        '-o',
        _knownHostsOption(knownHosts.path),
        '-o',
        'GlobalKnownHostsFile=/dev/null',
        '-i',
        privateKey.path,
        '-p',
        '$localPort',
        '$username@127.0.0.1',
        'hostname',
      ]).timeout(const Duration(seconds: 15));
      if (probe.exitCode != 0 || '${probe.stdout}'.trim().isEmpty) {
        throw HarnessSimulatorControllerException(
          'ssh_probe_failed',
          'SSH 身份验证失败：${probe.stderr}',
        );
      }
      return _HarnessSimulatorSshSession(
        tunnel: tunnel,
        localPort: localPort,
        username: username,
        privateKeyPath: privateKey.path,
        knownHostsPath: knownHosts.path,
        hostKeyFingerprint: fingerprint,
        hostname: '${probe.stdout}'.trim(),
      );
    } on Object {
      await tunnel.close();
      rethrow;
    }
  }

  Future<Directory> _resolveSshKeyRoot(String routingId) async {
    final base =
        _sshKeyRootOverride?.path ??
        (Platform.isWindows
            ? '${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}/Vibekits/simulator-ssh'
            : '${Platform.environment['HOME'] ?? Directory.systemTemp.path}/Library/Application Support/Vibekits/simulator-ssh');
    final root = Directory('$base/$routingId');
    await root.create(recursive: true);
    if (!Platform.isWindows) {
      await _processRunner('/bin/chmod', <String>['700', root.path]);
    }
    return root;
  }

  static String _sshExecutable() =>
      Platform.isWindows ? 'ssh.exe' : '/usr/bin/ssh';
  static String _scpExecutable() =>
      Platform.isWindows ? 'scp.exe' : '/usr/bin/scp';
  static String _sshKeygenExecutable() =>
      Platform.isWindows ? 'ssh-keygen.exe' : '/usr/bin/ssh-keygen';

  /// OpenSSH parses values passed through `-o` as configuration text even
  /// when the process argument itself is already a single argv entry. Quote
  /// paths so macOS' `Application Support` and Windows user directories do
  /// not get truncated at the first space.
  static String _knownHostsOption(String path) {
    final String normalized = path.replaceAll('\\', '/').replaceAll('"', r'\"');
    return 'UserKnownHostsFile="$normalized"';
  }

  Future<Map<String, Object?>> installCandidate(
    String routingId,
    String packagePath, {
    bool apply = true,
  }) async {
    final session = _requireSession(routingId);
    final File package = File(packagePath).absolute;
    if (!package.path.toLowerCase().endsWith('.zip') ||
        !await package.exists()) {
      throw const HarnessSimulatorControllerException(
        'invalid_candidate',
        '候选必须是存在的绝对 ZIP 文件',
      );
    }
    final int fileSize = await package.length();
    if (fileSize <= 0 || fileSize > SimulatorUpdateService.maxPackageBytes) {
      throw const HarnessSimulatorControllerException(
        'invalid_candidate',
        '候选包大小超出允许范围',
      );
    }
    final String checksum = (await sha256.bind(package.openRead()).first)
        .toString()
        .toLowerCase();
    final String fileName = package.uri.pathSegments.last;
    final Map<String, Object?> begin = _toolData(
      await call(routingId, 'vibekits.device.update_begin', <String, Object?>{
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': checksum,
      }),
    );
    final String uploadToken = '${begin['uploadToken'] ?? ''}';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(uploadToken)) {
      throw const HarnessSimulatorControllerException(
        'invalid_update_token',
        '远端没有返回有效上传令牌',
      );
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.putUrl(
        Uri.parse(
          'http://127.0.0.1:${session.localPort}${SimulatorUpdateService.uploadPath}',
        ),
      );
      request.persistentConnection = false;
      request.contentLength = fileSize;
      request.headers.set('x-vibekits-upload-token', uploadToken);
      await request.addStream(package.openRead());
      final response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HarnessSimulatorControllerException(
          'candidate_upload_failed',
          body.isEmpty ? '远端上传返回 HTTP ${response.statusCode}' : body,
        );
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map || decoded['token'] != uploadToken) {
        throw const HarnessSimulatorControllerException(
          'candidate_upload_failed',
          '远端没有确认相同候选令牌',
        );
      }
      final staged = Map<String, Object?>.from(decoded);
      if (!apply) return <String, Object?>{'uploaded': true, ...staged};
      final applied = _toolData(
        await call(routingId, 'vibekits.device.update_apply', <String, Object?>{
          'token': uploadToken,
        }),
      );
      return <String, Object?>{
        'uploaded': true,
        'sha256': checksum,
        'bytes': fileSize,
        ...applied,
      };
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, Object?> _toolData(Map<String, Object?> result) {
    final rawStructured = result['structuredContent'];
    if (rawStructured is! Map) {
      throw const HarnessSimulatorControllerException(
        'invalid_update_response',
        '远端升级工具响应缺少 structuredContent',
      );
    }
    final structured = Map<String, Object?>.from(rawStructured);
    if (structured['ok'] != true || structured['data'] is! Map) {
      throw HarnessSimulatorControllerException(
        'remote_update_rejected',
        '${structured['error'] ?? '远端拒绝升级请求'}',
      );
    }
    return Map<String, Object?>.from(structured['data']! as Map);
  }

  Future<Map<String, Object?>> disconnect(String routingId) async {
    final id = routingId.trim();
    _validateId(id);
    final session = _sessions.remove(id);
    await session?.ssh?.tunnel.close();
    await session?.tunnel.close();
    _publishStatus();
    return <String, Object?>{'connected': false, 'routingId': id};
  }

  Future<void> closeAll() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.ssh?.tunnel.close();
      await session.tunnel.close();
    }
    _publishStatus();
  }

  void _publishStatus() {
    if (!_changes.isClosed) _changes.add(status());
  }

  _HarnessSimulatorSession _requireSession(String routingId) {
    final id = routingId.trim();
    _validateId(id);
    final session = _sessions[id];
    if (session == null) {
      throw const HarnessSimulatorControllerException(
        'not_connected',
        '尚未连接该仿真机 ID，请先调用 vibekits.simulator.connect',
      );
    }
    return session;
  }

  static void _validateId(String value) {
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(value)) {
      throw const HarnessSimulatorControllerException(
        'invalid_id',
        '仿真机 ID 必须是 6～16 位数字',
      );
    }
  }

  static Map<String, Object?> _snapshot(_HarnessSimulatorSession session) =>
      <String, Object?>{
        'connected': !session.tunnel.closed,
        'routingId': session.routingId,
        'transport': session.forceRelay ? 'relay' : 'p2p_or_relay',
        'connectedAt': session.connectedAt.toIso8601String(),
        'toolCount': session.tools.length,
        'sshReady': session.ssh != null,
        if (session.ssh case final ssh?) ...<String, Object?>{
          'sshUsername': ssh.username,
          'sshHostKeyFingerprint': ssh.hostKeyFingerprint,
          'hostname': ssh.hostname,
        },
      };
}

final class _HarnessSimulatorSession {
  const _HarnessSimulatorSession({
    required this.routingId,
    required this.controllerRoutingId,
    required this.localPort,
    required this.forceRelay,
    required this.tunnel,
    required this.tools,
    required this.ssh,
    required this.connectedAt,
  });

  final String routingId;
  final String controllerRoutingId;
  final int localPort;
  final bool forceRelay;
  final RustDeskHarnessTunnelLease tunnel;
  final List<Map<String, Object?>> tools;
  final _HarnessSimulatorSshSession? ssh;
  final DateTime connectedAt;
}

final class _HarnessSimulatorSshSession {
  const _HarnessSimulatorSshSession({
    required this.tunnel,
    required this.localPort,
    required this.username,
    required this.privateKeyPath,
    required this.knownHostsPath,
    required this.hostKeyFingerprint,
    required this.hostname,
  });

  final RustDeskHarnessTunnelLease tunnel;
  final int localPort;
  final String username;
  final String privateKeyPath;
  final String knownHostsPath;
  final String hostKeyFingerprint;
  final String hostname;
}
