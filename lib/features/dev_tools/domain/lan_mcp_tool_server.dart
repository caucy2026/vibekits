import 'dart:convert';
import 'dart:io';

import 'harness_tool_bridge.dart';

/// MCP JSON-RPC endpoint exposed only while the user enables LAN MCP.
///
/// Discovery is handled separately by [LanPeerDiscoveryService]. This server
/// deliberately accepts only loopback and RFC1918 IPv4 clients so an
/// accidentally public interface cannot turn VibeKits into an Internet-facing
/// tool endpoint.
class LanMcpToolServer {
  LanMcpToolServer._(this._server, this._bridge);

  static const int maxRequestBytes = 1024 * 1024;
  static const String mcpProtocolVersion = '2025-06-18';

  final HttpServer _server;
  final VibekitsHarnessToolBridge _bridge;

  int get port => _server.port;
  Uri get loopbackEndpoint => Uri.parse('http://127.0.0.1:$port/mcp');

  static Future<LanMcpToolServer> start({
    VibekitsHarnessToolBridge? bridge,
    InternetAddress? bindAddress,
  }) async {
    final HttpServer server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
      shared: false,
    );
    final LanMcpToolServer result = LanMcpToolServer._(
      server,
      bridge ?? VibekitsHarnessToolBridge(),
    );
    server.listen(result._handle, onError: (_) {});
    return result;
  }

  Future<void> close() async {
    await _server.close(force: true);
    await _bridge.dispose();
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('MCP-Protocol-Version', mcpProtocolVersion);
    final String remoteAddress =
        request.connectionInfo?.remoteAddress.address ?? '';
    if (!_trustedIpv4(remoteAddress)) {
      await _writeHttpError(
        request.response,
        HttpStatus.forbidden,
        'forbidden',
      );
      return;
    }
    if (request.method != 'POST' || request.uri.path != '/mcp') {
      await _writeHttpError(request.response, HttpStatus.notFound, 'not_found');
      return;
    }
    try {
      final Map<String, Object?> payload = await _readObject(request);
      final Object? id = payload['id'];
      if (payload['jsonrpc'] != '2.0' || payload['method'] is! String) {
        await _rpcError(request.response, id, -32600, 'Invalid Request');
        return;
      }
      final String method = payload['method']! as String;
      final Object? rawParams = payload['params'];
      final Map<String, Object?> params = rawParams is Map
          ? Map<String, Object?>.from(rawParams)
          : const <String, Object?>{};
      switch (method) {
        case 'initialize':
          await _rpcResult(request.response, id, <String, Object?>{
            'protocolVersion': mcpProtocolVersion,
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{'listChanged': false},
            },
            'serverInfo': <String, Object?>{
              'name': 'VibeKits LAN MCP',
              'version': VibekitsHarnessToolBridge.protocolVersion,
            },
          });
        case 'notifications/initialized':
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
        case 'ping':
          await _rpcResult(request.response, id, const <String, Object?>{});
        case 'tools/list':
          await _rpcResult(request.response, id, <String, Object?>{
            'tools': <Map<String, Object?>>[
              for (final HarnessToolDefinition tool
                  in _bridge.executableCatalog)
                <String, Object?>{
                  'name': tool.id,
                  'title': tool.name,
                  'description': tool.description,
                  'inputSchema': tool.inputSchema,
                  'annotations': <String, Object?>{
                    'readOnlyHint': tool.risk == HarnessToolRisk.readOnly,
                    'destructiveHint': tool.risk == HarnessToolRisk.destructive,
                  },
                  '_meta': <String, Object?>{'vibekits/risk': tool.risk.name},
                },
            ],
          });
        case 'tools/call':
          final String name = '${params['name'] ?? ''}';
          final Object? rawArguments = params['arguments'];
          final HarnessToolCallResult result = await _bridge.invoke(
            toolId: name,
            arguments: rawArguments is Map
                ? Map<String, Object?>.from(rawArguments)
                : const <String, Object?>{},
            // Enabling LAN MCP is the user's provider-wide consent. Remote
            // Harness task delegation remains a separate approval surface.
            approve: (_) async => true,
          );
          final Map<String, Object?> structured = result.toJson();
          await _rpcResult(request.response, id, <String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': jsonEncode(structured)},
            ],
            'structuredContent': structured,
            'isError': !result.ok,
          });
        default:
          await _rpcError(request.response, id, -32601, 'Method not found');
      }
    } on FormatException catch (error) {
      await _rpcError(request.response, null, -32700, '$error');
    } on Object catch (error) {
      await _rpcError(request.response, null, -32603, '$error');
    }
  }

  static Future<Map<String, Object?>> _readObject(HttpRequest request) async {
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxRequestBytes) {
        throw const FormatException('MCP request exceeds 1 MiB');
      }
    }
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('MCP request is not an object');
    }
    return Map<String, Object?>.from(decoded);
  }

  static Future<void> _rpcResult(
    HttpResponse response,
    Object? id,
    Map<String, Object?> result,
  ) => _json(response, HttpStatus.ok, <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });

  static Future<void> _rpcError(
    HttpResponse response,
    Object? id,
    int code,
    String message,
  ) => _json(response, HttpStatus.ok, <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{'code': code, 'message': message},
  });

  static Future<void> _writeHttpError(
    HttpResponse response,
    int status,
    String error,
  ) => _json(response, status, <String, Object?>{'error': error});

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> value,
  ) async {
    response.statusCode = status;
    response.write(jsonEncode(value));
    await response.close();
  }

  static bool _trustedIpv4(String value) {
    if (value == '127.0.0.1') return true;
    final List<String> parts = value.split('.');
    if (parts.length != 4) return false;
    final List<int> bytes = <int>[];
    for (final String part in parts) {
      final int? parsed = int.tryParse(part);
      if (parsed == null || parsed < 0 || parsed > 255) return false;
      bytes.add(parsed);
    }
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }
}
