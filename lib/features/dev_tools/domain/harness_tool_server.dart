import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'harness_tool_bridge.dart';

/// Loopback-only adapter used by the bundled MCP stdio process.
///
/// The random bearer token is passed only to the child process environment.
/// Requests, responses and logs never contain the user's model credential.
class HarnessToolServer {
  HarnessToolServer._(
    this._server,
    this._bridge,
    this._approve,
    this.token,
    this._connectionFile,
  );

  static const int maxRequestBytes = 1024 * 1024;

  final HttpServer _server;
  final VibekitsHarnessToolBridge _bridge;
  final HarnessToolApproval _approve;
  final String token;
  final File? _connectionFile;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<HarnessToolServer> start({
    VibekitsHarnessToolBridge? bridge,
    HarnessToolApproval? approve,
    File? connectionFile,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final HarnessToolServer result = HarnessToolServer._(
      server,
      bridge ?? VibekitsHarnessToolBridge(),
      approve ?? _denyRiskyTool,
      _randomToken(),
      connectionFile,
    );
    server.listen(result._handle, onError: (_) {});
    if (connectionFile != null) {
      try {
        await result._publishConnection();
      } on Object {
        await server.close(force: true);
        rethrow;
      }
    }
    return result;
  }

  static File defaultConnectionFile() {
    final String base;
    if (Platform.isWindows) {
      base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      return File(
        '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Mcp'
        '${Platform.pathSeparator}tool-bridge.json',
      );
    }
    final String home =
        Platform.environment['HOME'] ?? Directory.systemTemp.path;
    if (Platform.isMacOS) {
      return File(
        '$home${Platform.pathSeparator}Library${Platform.pathSeparator}'
        'Application Support${Platform.pathSeparator}Vibekits'
        '${Platform.pathSeparator}Mcp${Platform.pathSeparator}tool-bridge.json',
      );
    }
    base =
        Platform.environment['XDG_RUNTIME_DIR'] ??
        '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share';
    return File(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Mcp'
      '${Platform.pathSeparator}tool-bridge.json',
    );
  }

  Future<void> close() async {
    await _removePublishedConnection();
    await _server.close(force: true);
    await _bridge.dispose();
  }

  Future<void> _publishConnection() async {
    final File target = _connectionFile!;
    await target.parent.create(recursive: true);
    final File temporary = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'endpoint': endpoint.toString(),
        'token': token,
        'processId': pid,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (!Platform.isWindows) {
      final ProcessResult chmod = await Process.run('chmod', <String>[
        '600',
        temporary.path,
      ], runInShell: false);
      if (chmod.exitCode != 0) {
        await temporary.delete();
        throw StateError('无法保护 VibeKits MCP connection file');
      }
    }
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<void> _removePublishedConnection() async {
    final File? file = _connectionFile;
    if (file == null || !await file.exists()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['token'] == token) {
        await file.delete();
      }
    } on Object {
      // Never delete a file that cannot be proven to belong to this server.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $token') {
      await _json(request.response, HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
      return;
    }
    try {
      if (request.method == 'GET' && request.uri.path == '/catalog') {
        await _json(request.response, HttpStatus.ok, _bridge.exportCatalog());
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/invoke') {
        final List<int> bytes = <int>[];
        await for (final List<int> chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > maxRequestBytes) {
            throw const FormatException('工具请求超过 1 MiB');
          }
        }
        final Object? decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw const FormatException('工具请求不是对象');
        final Map<String, Object?> payload = Map<String, Object?>.from(decoded);
        final Object? rawArguments = payload['arguments'];
        final HarnessToolCallResult result = await _bridge.invoke(
          toolId: '${payload['toolId'] ?? ''}',
          arguments: rawArguments is Map
              ? Map<String, Object?>.from(rawArguments)
              : const <String, Object?>{},
          approve: _approve,
        );
        await _json(request.response, HttpStatus.ok, result.toJson());
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/native-approval') {
        final Map<String, Object?> payload = await _readObject(request);
        final String toolName = '${payload['toolName'] ?? 'native-tool'}';
        final String reason = '${payload['reason'] ?? ''}';
        final String workspace = '${payload['workspace'] ?? ''}';
        final bool allowed = await _approve(
          HarnessToolApprovalRequest(
            tool: HarnessToolDefinition(
              id: 'harness.native.${_safeId(toolName)}',
              name: 'Harness 原生工具：$toolName',
              description: reason.isEmpty ? '官方 Harness 请求执行原生工具。' : reason,
              risk: HarnessToolRisk.writesData,
              inputSchema: const <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
              available: true,
            ),
            arguments: <String, Object?>{
              if (reason.isNotEmpty) 'reason': reason,
              if (payload['callId'] != null) 'callId': '${payload['callId']}',
            },
            target: workspace,
          ),
        );
        await _json(request.response, HttpStatus.ok, <String, Object?>{
          'allowed': allowed,
        });
        return;
      }
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'error': 'not_found',
      });
    } on Object catch (error) {
      await _json(request.response, HttpStatus.badRequest, <String, Object?>{
        'error': '$error',
      });
    }
  }

  static Future<Map<String, Object?>> _readObject(HttpRequest request) async {
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxRequestBytes) {
        throw const FormatException('工具请求超过 1 MiB');
      }
    }
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('工具请求不是对象');
    return Map<String, Object?>.from(decoded);
  }

  static String _safeId(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> value,
  ) async {
    response.statusCode = status;
    response.write(jsonEncode(value));
    await response.close();
  }

  static Future<bool> _denyRiskyTool(
    HarnessToolApprovalRequest request,
  ) async => false;

  static String _randomToken() {
    final Random random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }
}
