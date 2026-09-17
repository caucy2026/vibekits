import 'dart:convert';
import 'dart:io';

import 'harness_tool_bridge.dart';
import 'lmcp_inbound_call_hub.dart';
import 'remote_simulation_activity.dart';
import 'simulator_control_server.dart';
import 'simulator_update_service.dart';

/// MCP JSON-RPC endpoint exposed only while the user enables LAN MCP.
///
/// Discovery is handled separately by [LanPeerDiscoveryService]. This server
/// deliberately accepts only loopback and RFC1918 IPv4 clients so an
/// accidentally public interface cannot turn VibeKits into an Internet-facing
/// tool endpoint.
class LanMcpToolServer {
  LanMcpToolServer._(
    this._server,
    this._bridge, {
    required this.allowSimulatorUpdateUpload,
    required this.trustSimulatorCallerAfterEnable,
    required this.authorizeSimulatorCaller,
    required this.sensitiveApprovalTimeout,
  });

  static const int maxRequestBytes = 1024 * 1024;
  static const String mcpProtocolVersion = '2025-06-18';

  final HttpServer _server;
  final VibekitsHarnessToolBridge _bridge;
  final bool allowSimulatorUpdateUpload;
  final bool trustSimulatorCallerAfterEnable;
  final SimulatorCallerAuthorizer? authorizeSimulatorCaller;
  final Duration sensitiveApprovalTimeout;
  int _traceSequence = 0;

  int get port => _server.port;
  Uri get loopbackEndpoint => Uri.parse('http://127.0.0.1:$port/mcp');

  static Future<LanMcpToolServer> start({
    VibekitsHarnessToolBridge? bridge,
    InternetAddress? bindAddress,
    int port = 0,
    bool allowSimulatorUpdateUpload = false,
    bool trustSimulatorCallerAfterEnable = false,
    SimulatorCallerAuthorizer? authorizeSimulatorCaller,
    Duration sensitiveApprovalTimeout = const Duration(minutes: 2),
  }) async {
    final HttpServer server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    final LanMcpToolServer result = LanMcpToolServer._(
      server,
      bridge ?? VibekitsHarnessToolBridge(),
      allowSimulatorUpdateUpload: allowSimulatorUpdateUpload,
      trustSimulatorCallerAfterEnable: trustSimulatorCallerAfterEnable,
      authorizeSimulatorCaller: authorizeSimulatorCaller,
      sensitiveApprovalTimeout: sensitiveApprovalTimeout,
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
    if (request.method == 'PUT' &&
        request.uri.path == SimulatorUpdateService.uploadPath) {
      if (!allowSimulatorUpdateUpload || remoteAddress != '127.0.0.1') {
        await _writeHttpError(
          request.response,
          HttpStatus.forbidden,
          'simulator_update_upload_disabled',
        );
        return;
      }
      await _handleSimulatorUpdateUpload(request);
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
          final Map<String, Object?> arguments = rawArguments is Map
              ? Map<String, Object?>.from(rawArguments)
              : const <String, Object?>{};
          final HarnessToolDefinition? definition = _bridge.executableCatalog
              .where((tool) => tool.id == name)
              .firstOrNull;
          final String callerId =
              request.headers.value('x-vibekits-caller-id') ?? '';
          final activity = RemoteSimulationActivityHub.instance.begin(
            direction: RemoteSimulationActivityDirection.incoming,
            peerId: callerId,
            action: definition?.name ?? name,
            arguments: arguments,
          );
          final bool requiresTargetApproval =
              definition != null && _requiresTargetApproval(name);
          final bool rememberedSimulatorAuthorization = requiresTargetApproval
              ? await _isRememberedSimulatorCaller(
                  request,
                  remoteAddress: remoteAddress,
                )
              : false;
          LmcpInboundCallHandle? approvalCall;
          if (requiresTargetApproval && !rememberedSimulatorAuthorization) {
            final traceId =
                'simulator-${DateTime.now().microsecondsSinceEpoch}-${_traceSequence++}';
            approvalCall = LmcpInboundCallHub.instance.begin(
              traceId: traceId,
              callerAppId: 'VibeKits 远程仿真',
              callerInstanceId: callerId,
              callerAddress: remoteAddress,
              toolId: name,
              toolName: definition.name,
              arguments: arguments,
              scopeSummary: '本次操作需目标机明确批准',
              approvalRequired: true,
            );
            final allowed = await approvalCall.waitForApproval().timeout(
              sensitiveApprovalTimeout,
              onTimeout: () => false,
            );
            if (!allowed) {
              approvalCall.fail('目标机未批准操作');
              activity.fail('目标机未批准操作');
              final denied = const HarnessToolCallResult.cancelled();
              await _rpcResult(request.response, id, <String, Object?>{
                'content': <Map<String, Object?>>[
                  <String, Object?>{
                    'type': 'text',
                    'text': jsonEncode(denied.toJson()),
                  },
                ],
                'structuredContent': denied.toJson(),
                'isError': true,
              });
              break;
            }
          }
          late final HarnessToolCallResult result;
          try {
            result = await _bridge.invoke(
              toolId: name,
              arguments: arguments,
              preauthorized:
                  approvalCall != null || rememberedSimulatorAuthorization,
              approve: (_) async => true,
            );
            if (result.ok) {
              approvalCall?.succeed();
              activity.succeed('远程操作已完成');
            } else {
              approvalCall?.fail(result.error);
              activity.fail(result.error ?? '远程操作失败');
            }
          } on Object catch (error) {
            approvalCall?.fail('$error');
            activity.fail(error);
            rethrow;
          }
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

  static bool _requiresTargetApproval(String toolId) =>
      toolId == VibekitsHarnessToolBridge.deviceScreenshotId ||
      toolId == VibekitsHarnessToolBridge.deviceAppInstallId ||
      toolId == VibekitsHarnessToolBridge.deviceAppUninstallId ||
      toolId == VibekitsHarnessToolBridge.deviceSshAuthorizeId ||
      toolId == VibekitsHarnessToolBridge.deviceSshRevokeId;

  Future<bool> _isRememberedSimulatorCaller(
    HttpRequest request, {
    required String remoteAddress,
  }) async {
    if (!trustSimulatorCallerAfterEnable ||
        !allowSimulatorUpdateUpload ||
        remoteAddress != '127.0.0.1' ||
        authorizeSimulatorCaller == null) {
      return false;
    }
    final String callerId =
        request.headers.value('x-vibekits-caller-id')?.trim() ?? '';
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(callerId)) return false;
    try {
      return await authorizeSimulatorCaller!(callerId);
    } on Object {
      return false;
    }
  }

  Future<void> _handleSimulatorUpdateUpload(HttpRequest request) async {
    try {
      final String uploadToken =
          request.headers.value('x-vibekits-upload-token') ?? '';
      final result = await SimulatorUpdateService.instance.receive(
        stream: request,
        uploadToken: uploadToken,
        contentLength: request.contentLength,
      );
      await _json(request.response, HttpStatus.ok, result);
    } on FormatException catch (error) {
      await _json(request.response, HttpStatus.badRequest, <String, Object?>{
        'error': '$error',
      });
    } on Object catch (error) {
      await _json(
        request.response,
        HttpStatus.internalServerError,
        <String, Object?>{'error': '$error'},
      );
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
