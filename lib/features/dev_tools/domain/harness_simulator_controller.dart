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
  Future<List<Map<String, Object?>>> initializeAndList(int localPort);

  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments,
  );
}

final class _LoopbackHarnessSimulatorMcpClient
    implements HarnessSimulatorMcpClient {
  const _LoopbackHarnessSimulatorMcpClient();

  static const String _protocolVersion = '2025-06-18';
  static const int _maxResponseBytes = 1024 * 1024;

  @override
  Future<List<Map<String, Object?>>> initializeAndList(int localPort) async {
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
    );
    if (initialized['protocolVersion'] != _protocolVersion) {
      throw const HarnessSimulatorControllerException(
        'incompatible_protocol',
        '远端仿真机 MCP 协议不兼容',
      );
    }
    await _notification(localPort, 'notifications/initialized');
    final result = await _rpc(
      localPort,
      2,
      'tools/list',
      const <String, Object?>{},
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
    Map<String, Object?> arguments,
  ) => _rpc(localPort, 3, 'tools/call', <String, Object?>{
    'name': toolId,
    'arguments': arguments,
  });

  Future<Map<String, Object?>> _rpc(
    int port,
    int id,
    String method,
    Map<String, Object?> params,
  ) async {
    final response = await _post(port, <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
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

  Future<void> _notification(int port, String method) async {
    await _post(port, <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': const <String, Object?>{},
    });
  }

  Future<Map<String, Object?>> _post(
    int port,
    Map<String, Object?> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port/mcp'))
          .timeout(const Duration(seconds: 8));
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('MCP-Protocol-Version', _protocolVersion);
      final bytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
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
  }) : _resolveHost =
           resolveHost ?? RustDeskHarnessShareService.ensureHostAvailable,
       _openTunnel = openTunnel ?? _defaultOpenTunnel,
       _allocatePort =
           allocatePort ?? RustDeskHarnessShareService.allocateTunnelPort,
       _mcpClient = mcpClient ?? const _LoopbackHarnessSimulatorMcpClient();

  static final HarnessSimulatorController shared = HarnessSimulatorController();

  final HarnessSimulatorHostResolver _resolveHost;
  final HarnessSimulatorTunnelOpener _openTunnel;
  final HarnessSimulatorPortAllocator _allocatePort;
  final HarnessSimulatorMcpClient _mcpClient;
  final Map<String, _HarnessSimulatorSession> _sessions =
      <String, _HarnessSimulatorSession>{};

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
          .initializeAndList(localPort)
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
      final session = _HarnessSimulatorSession(
        routingId: id,
        localPort: localPort,
        forceRelay: forceRelay,
        tunnel: tunnel,
        tools: tools,
        connectedAt: DateTime.now().toUtc(),
      );
      _sessions[id] = session;
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
    return _mcpClient.call(session.localPort, name, arguments);
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
    await session?.tunnel.close();
    return <String, Object?>{'connected': false, 'routingId': id};
  }

  Future<void> closeAll() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.tunnel.close();
    }
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
      };
}

final class _HarnessSimulatorSession {
  const _HarnessSimulatorSession({
    required this.routingId,
    required this.localPort,
    required this.forceRelay,
    required this.tunnel,
    required this.tools,
    required this.connectedAt,
  });

  final String routingId;
  final int localPort;
  final bool forceRelay;
  final RustDeskHarnessTunnelLease tunnel;
  final List<Map<String, Object?>> tools;
  final DateTime connectedAt;
}
