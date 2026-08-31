import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'lan_peer_discovery_service.dart';
import 'lmcp_exposure_server.dart';
import 'mcp_capability_models.dart';

class LmcpRemoteException implements Exception {
  const LmcpRemoteException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'LmcpRemoteException($code): $message';
}

/// LMCP/2 client with certificate fingerprint pinning.
///
/// Discovery data is untrusted. Every HTTPS connection is therefore created
/// directly, its peer certificate is hashed, and only the fingerprint from the
/// latest announcement is accepted before any HTTP bytes are exchanged.
class LmcpRemoteClient {
  LmcpRemoteClient({
    this.timeout = const Duration(seconds: 8),
    this.callTimeout = const Duration(seconds: 120),
    this.maxResponseBytes = 1024 * 1024,
  });

  static const String mcpProtocolVersion = '2025-06-18';

  final Duration timeout;
  final Duration callTimeout;
  final int maxResponseBytes;

  Future<List<McpToolInterface>> loadTools(VibekitsLanPeer peer) async {
    _requireCallablePeer(peer);
    int id = 1;
    final Map<String, Object?> initialized = await _rpc(
      peer: peer,
      endpoint: peer.catalogUri,
      id: id++,
      method: 'initialize',
      params: <String, Object?>{
        'protocolVersion': mcpProtocolVersion,
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'VibeKits',
          'version': VibekitsLmcpExposureServer.currentAppVersion,
        },
      },
    );
    final Object? rawProtocol = initialized['protocolVersion'];
    if (rawProtocol != mcpProtocolVersion) {
      throw LmcpRemoteException(
        'unsupported_protocol',
        '远端采用不兼容的 MCP 协议版本：$rawProtocol',
      );
    }
    await _notification(
      peer: peer,
      endpoint: peer.catalogUri,
      method: 'notifications/initialized',
      params: const <String, Object?>{},
    );

    final List<McpToolInterface> tools = <McpToolInterface>[];
    final List<Map<String, Object?>> rawCatalogTools = <Map<String, Object?>>[];
    final Set<String> cursors = <String>{};
    String? cursor;
    for (int page = 0; page < 20; page++) {
      final Map<String, Object?> result = await _rpc(
        peer: peer,
        endpoint: peer.catalogUri,
        id: id++,
        method: 'tools/list',
        params: <String, Object?>{'cursor': ?cursor},
      );
      final Object? rawTools = result['tools'];
      if (rawTools is! List) {
        throw const LmcpRemoteException(
          'invalid_catalog',
          '远端 tools/list 没有返回工具数组',
        );
      }
      for (final Object? item in rawTools) {
        if (item is! Map) {
          throw const LmcpRemoteException(
            'invalid_catalog',
            '远端 tools/list 包含非对象工具',
          );
        }
        final Map<String, Object?> rawTool = Map<String, Object?>.from(item);
        final McpToolInterface tool = McpToolInterface.fromJson(rawTool);
        if (tool.name.isEmpty ||
            tools.any((candidate) => candidate.name == tool.name)) {
          throw const LmcpRemoteException(
            'invalid_catalog',
            '远端 tools/list 包含空名称或重复工具',
          );
        }
        rawCatalogTools.add(rawTool);
        tools.add(tool);
      }
      final Object? next = result['nextCursor'];
      if (next == null || '$next'.isEmpty) break;
      cursor = '$next';
      if (!cursors.add(cursor)) {
        throw const LmcpRemoteException(
          'invalid_catalog',
          '远端 tools/list 返回了循环游标',
        );
      }
      if (page == 19) {
        throw const LmcpRemoteException('catalog_limit', '远端工具目录分页超过安全上限');
      }
    }

    final String advertisedDigest = peer.capabilityDigest.toLowerCase();
    if (RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(advertisedDigest)) {
      final String actual =
          'sha256:${sha256.convert(utf8.encode(_canonicalJson(<String, Object?>{
            // The digest covers the provider's complete catalog, including
            // extensions unknown to this client. Re-serializing the reduced
            // UI model would discard or reshape fields such as structured
            // risk metadata and incorrectly reject a valid provider.
            'tools': rawCatalogTools,
            'nextCursor': null,
          })))}';
      if (!_constantTimeEquals(actual, advertisedDigest)) {
        throw const LmcpRemoteException(
          'catalog_digest_mismatch',
          '远端工具目录与发现公告摘要不一致',
        );
      }
    }
    return List<McpToolInterface>.unmodifiable(tools);
  }

  Future<Map<String, Object?>> callTool({
    required VibekitsLanPeer peer,
    required String name,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    _requireCallablePeer(peer);
    if (name.trim().isEmpty) {
      throw const LmcpRemoteException('invalid_arguments', 'MCP 工具名称不能为空');
    }
    final Map<String, Object?> result = await _rpc(
      peer: peer,
      endpoint: peer.callUri,
      id: 1,
      method: 'tools/call',
      params: <String, Object?>{'name': name, 'arguments': arguments},
      requestTimeout: callTimeout,
    );
    final Map<Object?, Object?> structured = result['structuredContent'] is Map
        ? result['structuredContent']! as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final Object? responseInstanceId =
        result['instanceId'] ?? structured['instanceId'];
    final Object? responseTool = result['tool'] ?? structured['tool'];
    final Object? responseRevision =
        result['catalogRevision'] ?? structured['catalogRevision'];
    if (responseInstanceId != peer.instanceId || responseTool != name) {
      throw const LmcpRemoteException(
        'response_identity_mismatch',
        '远端工具结果的实例或工具身份不匹配',
      );
    }
    if (peer.catalogRevision.isNotEmpty &&
        '${responseRevision ?? ''}' != peer.catalogRevision) {
      throw const LmcpRemoteException(
        'catalog_revision_mismatch',
        '远端工具结果的目录版本已经变化',
      );
    }
    return result;
  }

  Future<Map<String, Object?>> _rpc({
    required VibekitsLanPeer peer,
    required Uri endpoint,
    required int id,
    required String method,
    required Map<String, Object?> params,
    Duration? requestTimeout,
  }) async {
    final Map<String, Object?> response = await _post(
      peer,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      },
      acceptedStatuses: const <int>{HttpStatus.ok},
      requestTimeout: requestTimeout,
    );
    if (response['jsonrpc'] != '2.0' || response['id'] != id) {
      throw const LmcpRemoteException(
        'invalid_response',
        '远端返回了不匹配的 JSON-RPC 响应',
      );
    }
    if (response['error'] != null) {
      final Object? error = response['error'];
      final String message = error is Map
          ? '${error['message'] ?? 'remote MCP error'}'
          : 'remote MCP error';
      throw LmcpRemoteException('remote_error', _bounded(message, 512));
    }
    final Object? result = response['result'];
    if (result is! Map) {
      throw const LmcpRemoteException(
        'invalid_response',
        '远端 JSON-RPC 响应缺少结果对象',
      );
    }
    return Map<String, Object?>.from(result);
  }

  Future<void> _notification({
    required VibekitsLanPeer peer,
    required Uri endpoint,
    required String method,
    required Map<String, Object?> params,
  }) async {
    await _post(
      peer,
      endpoint,
      <String, Object?>{'jsonrpc': '2.0', 'method': method, 'params': params},
      acceptedStatuses: const <int>{HttpStatus.ok, HttpStatus.accepted},
      allowEmpty: true,
    );
  }

  Future<Map<String, Object?>> _post(
    VibekitsLanPeer peer,
    Uri endpoint,
    Map<String, Object?> payload, {
    required Set<int> acceptedStatuses,
    bool allowEmpty = false,
    Duration? requestTimeout,
  }) async {
    final Duration operationTimeout = requestTimeout ?? timeout;
    final HttpClient client = _pinnedClient(
      peer.instanceKeyFingerprint,
      operationTimeout,
    );
    try {
      final HttpClientRequest request = await client
          .postUrl(endpoint)
          .timeout(operationTimeout);
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      final List<int> requestBytes = utf8.encode(jsonEncode(payload));
      // Some small Windows MCP servers deliberately reject chunked request
      // bodies. LMCP requests are bounded and already materialized, so always
      // send an explicit Content-Length for broad HTTP/1.1 interoperability.
      request.contentLength = requestBytes.length;
      request.add(requestBytes);
      final HttpClientResponse response = await request.close().timeout(
        operationTimeout,
      );
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(operationTimeout)) {
        bytes.add(chunk);
        if (bytes.length > maxResponseBytes) {
          throw const LmcpRemoteException(
            'response_too_large',
            '远端 MCP 响应超过 1 MiB 安全上限',
          );
        }
      }
      final Uint8List body = bytes.takeBytes();
      if (!acceptedStatuses.contains(response.statusCode)) {
        throw LmcpRemoteException(
          'http_${response.statusCode}',
          '远端 MCP HTTP 状态 ${response.statusCode}',
        );
      }
      if (body.isEmpty && allowEmpty) return const <String, Object?>{};
      final Object? decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        throw const LmcpRemoteException(
          'invalid_response',
          '远端 MCP 响应不是 JSON 对象',
        );
      }
      return Map<String, Object?>.from(decoded);
    } on LmcpRemoteException {
      rethrow;
    } on TimeoutException {
      throw const LmcpRemoteException('timeout', '远端 MCP 调用超时');
    } on HandshakeException {
      throw const LmcpRemoteException(
        'tls_handshake_failed',
        '远端 MCP TLS 握手失败',
      );
    } on HttpException {
      throw const LmcpRemoteException(
        'invalid_http_response',
        '远端 MCP 在完整 HTTP 响应前断开连接',
      );
    } on SocketException {
      throw const LmcpRemoteException('connection_failed', '无法连接远端 MCP 端点');
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _pinnedClient(
    String advertisedFingerprint,
    Duration operationTimeout,
  ) {
    final String expected = advertisedFingerprint.toLowerCase();
    final HttpClient client = HttpClient()
      ..connectionTimeout = operationTimeout
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) async {
          if (uri.scheme != 'https' || proxyHost != null || proxyPort != null) {
            throw const LmcpRemoteException(
              'unsafe_transport',
              'LMCP/2 仅允许直连 HTTPS 私网端点',
            );
          }
          final ConnectionTask<SecureSocket> task =
              await SecureSocket.startConnect(
                uri.host,
                uri.port,
                onBadCertificate: (_) => true,
              );
          final Future<Socket> checked = task.socket.then<Socket>((socket) {
            final X509Certificate? certificate = socket.peerCertificate;
            final String actual = certificate == null
                ? ''
                : 'sha256:${sha256.convert(certificate.der)}';
            if (!_constantTimeEquals(actual, expected)) {
              socket.destroy();
              throw const LmcpRemoteException(
                'certificate_mismatch',
                '远端 TLS 证书指纹与发现公告不一致',
              );
            }
            return socket;
          });
          return ConnectionTask.fromSocket<Socket>(checked, task.cancel);
        };
    return client;
  }

  static void _requireCallablePeer(VibekitsLanPeer peer) {
    if (!peer.supportsLmcp2Calls) {
      throw const LmcpRemoteException(
        'unsupported_peer',
        '该节点没有可安全调用的 LMCP/2 HTTPS 端点',
      );
    }
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    int difference = 0;
    for (int index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  static String _canonicalJson(Object? value) =>
      jsonEncode(_canonicalize(value));

  static Object? _canonicalize(Object? value) {
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is Map) {
      final List<String> keys = value.keys.map((key) => '$key').toList()
        ..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonicalize(value[key]),
      };
    }
    return value;
  }

  static String _bounded(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
