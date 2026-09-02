import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import 'harness_tool_bridge.dart';
import 'lan_peer_discovery_service.dart';
import 'lmcp_caller_auth.dart';
import 'lmcp_inbound_call_hub.dart';
import 'lmcp_capacity_manager.dart';
import 'platform_credential_store.dart';

typedef LmcpCredentialReader = Future<String?> Function(String key);
typedef LmcpCredentialWriter = Future<void> Function(String key, String value);

class LmcpInstanceCertificate {
  const LmcpInstanceCertificate({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;
}

/// Loads or creates the persistent TLS identity advertised by LMCP/2.
///
/// The private key is stored in the platform credential manager rather than in
/// the LMCP discovery packet or a workspace file. EC P-256 keeps the Windows
/// Credential Manager values safely below its per-entry size limit.
class LmcpCertificateStore {
  LmcpCertificateStore({
    LmcpCredentialReader? readCredential,
    LmcpCredentialWriter? writeCredential,
  }) : _readCredential = readCredential ?? PlatformCredentialStore.read,
       _writeCredential = writeCredential ?? PlatformCredentialStore.write;

  static const String _certificateKey = 'lmcp-v2-instance-certificate';
  static const String _privateKeyKey = 'lmcp-v2-instance-private-key';

  final LmcpCredentialReader _readCredential;
  final LmcpCredentialWriter _writeCredential;

  Future<LmcpInstanceCertificate> loadOrCreate({
    required String commonName,
  }) async {
    final String? certificate = await _readCredential(_certificateKey);
    final String? privateKey = await _readCredential(_privateKeyKey);
    if (certificate?.trim().isNotEmpty == true &&
        privateKey?.trim().isNotEmpty == true) {
      try {
        return _validated(certificate!, privateKey!);
      } on Object {
        // A partial/corrupt credential update must not permanently brick MCP.
        // Keep exposure closed and replace both values with one fresh pair.
      }
    }

    final AsymmetricKeyPair<PublicKey, PrivateKey> pair =
        CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final ECPrivateKey generatedPrivate = pair.privateKey as ECPrivateKey;
    final ECPublicKey generatedPublic = pair.publicKey as ECPublicKey;
    final String csr = X509Utils.generateEccCsrPem(
      <String, String>{'CN': _safeCommonName(commonName), 'O': 'VibeKits'},
      generatedPrivate,
      generatedPublic,
      signingAlgorithm: 'SHA-256',
    );
    final String generatedCertificate = X509Utils.generateSelfSignedCertificate(
      generatedPrivate,
      csr,
      3650,
      cA: false,
      serialNumber: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
    );
    final String generatedPrivatePem = CryptoUtils.encodeEcPrivateKeyToPem(
      generatedPrivate,
    );
    final LmcpInstanceCertificate identity = _validated(
      generatedCertificate,
      generatedPrivatePem,
    );
    // Store the key first. A later certificate-write failure is fail-closed:
    // the next attempt creates a new complete pair rather than advertising a
    // certificate whose private key was not persisted.
    await _writeCredential(_privateKeyKey, identity.privateKeyPem);
    try {
      await _writeCredential(_certificateKey, identity.certificatePem);
    } on Object {
      await _writeCredential(_privateKeyKey, '');
      rethrow;
    }
    return identity;
  }

  static LmcpInstanceCertificate _validated(
    String certificatePem,
    String privateKeyPem,
  ) {
    SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
    // Creating the context above proves the PEM pair is accepted by the
    // platform TLS implementation. Hash the exact DER encoded by the PEM.
    final Uint8List der = CryptoUtils.getBytesFromPEMString(certificatePem);
    final String fingerprint = 'sha256:${sha256.convert(der)}';
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('LMCP/2 TLS certificate fingerprint invalid');
    }
    return LmcpInstanceCertificate(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      fingerprint: fingerprint,
    );
  }

  static String _safeCommonName(String value) {
    final String result = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f,=+<>#;]'), '-')
        .trim();
    if (result.isEmpty) return 'VibeKits LMCP';
    return result.length <= 64 ? result : result.substring(0, 64);
  }
}

class LmcpProtocolException implements Exception {
  const LmcpProtocolException(this.code, this.message, [this.data]);

  final int code;
  final String message;
  final Object? data;
}

class LmcpCallerIdentity {
  const LmcpCallerIdentity({
    this.appId = '',
    this.instanceId = '',
    this.address = '',
  });

  final String appId;
  final String instanceId;
  final String address;
}

typedef LmcpToolInvocationRunner =
    Future<HarnessToolCallResult> Function(
      HarnessToolDefinition tool,
      Map<String, Object?> arguments,
      LmcpInboundCallCancellation cancellation,
      LmcpInboundCallHandle call,
    );

class _LmcpInvocationFailure {
  const _LmcpInvocationFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class _LmcpInvocationTerminated {
  const _LmcpInvocationTerminated();
}

/// Standard MCP 2025-06-18 protocol surface backed by the same bridge used by
/// the local Harness. Consequently the normal risk approval and activity audit
/// paths remain mandatory for remote calls as well.
class VibekitsLmcpProtocol {
  VibekitsLmcpProtocol({
    required this.instanceId,
    required this.serverVersion,
    required VibekitsHarnessToolBridge bridge,
    this.pageSize = 100,
    LmcpInboundCallHub? callHub,
    LmcpToolInvocationRunner? invocationRunner,
    LmcpCapacityLeaseManager? capacityManager,
  }) : _callHub = callHub ?? LmcpInboundCallHub.instance,
       _invocationRunner =
           invocationRunner ??
           ((
             HarnessToolDefinition tool,
             Map<String, Object?> arguments,
             LmcpInboundCallCancellation cancellation,
             LmcpInboundCallHandle call,
           ) async {
             cancellation.throwIfCancelled();
             final HarnessToolCallResult result = await bridge.invoke(
               toolId: tool.id,
               arguments: arguments,
               preauthorized: true,
               // Enabling LMCP exposure is the persisted provider-wide
               // authorization. Runtime disclosure is not a second approval.
               approve: (_) async => true,
             );
             cancellation.throwIfCancelled();
             return result;
           }),
       capacityManager =
           capacityManager ?? LmcpCapacityLeaseManager(capacity: 8),
       tools = List<HarnessToolDefinition>.unmodifiable(
         bridge.executableCatalog,
       ) {
    catalogRevision = currentCatalogRevision;
  }

  static const String protocolVersion = '2025-06-18';
  // The monotonic application build number changes together with the
  // executable catalog. The complete schema is independently protected by
  // [capabilityDigest].
  static const String currentCatalogRevision = '2147';

  final String instanceId;
  final String serverVersion;
  final LmcpInboundCallHub _callHub;
  final LmcpToolInvocationRunner _invocationRunner;
  final int pageSize;
  final List<HarnessToolDefinition> tools;
  final LmcpCapacityLeaseManager capacityManager;
  late final String catalogRevision;
  int _traceSequence = 0;

  List<Map<String, Object?>> get toolCatalog => <Map<String, Object?>>[
    ..._capacityToolCatalog,
    for (final HarnessToolDefinition tool in tools)
      <String, Object?>{
        'name': tool.id,
        'title': tool.name,
        'description': tool.description,
        'inputSchema': tool.inputSchema,
        'annotations': <String, Object?>{
          'readOnlyHint': tool.risk == HarnessToolRisk.readOnly,
          'destructiveHint': tool.risk == HarnessToolRisk.destructive,
          'idempotentHint': tool.risk == HarnessToolRisk.readOnly,
          'openWorldHint': tool.risk == HarnessToolRisk.controlsDevice,
        },
        'risk': tool.risk.name,
      },
  ];

  static final List<Map<String, Object?>> _capacityToolCatalog =
      <Map<String, Object?>>[
        _capacityTool(
          'lmcp.node.status',
          '查询作战单位实时容量',
          const <String, Object?>{},
          const <String>[],
        ),
        _capacityTool(
          'lmcp.capacity.reserve',
          '原子预约作战单位执行槽位',
          <String, Object?>{
            'toolName': const <String, Object?>{'type': 'string'},
            'idempotencyKey': const <String, Object?>{'type': 'string'},
            'commanderId': const <String, Object?>{'type': 'string'},
            'requestedSlots': const <String, Object?>{
              'type': 'integer',
              'minimum': 1,
            },
            'ttlSeconds': const <String, Object?>{
              'type': 'integer',
              'minimum': 10,
              'maximum': 120,
            },
            'scopeDigest': const <String, Object?>{'type': 'string'},
          },
          const <String>[
            'toolName',
            'idempotencyKey',
            'commanderId',
            'requestedSlots',
            'ttlSeconds',
            'scopeDigest',
          ],
        ),
        _capacityTool(
          'lmcp.capacity.renew',
          '续租已预约的执行槽位',
          <String, Object?>{
            'leaseId': const <String, Object?>{'type': 'string'},
            'leaseToken': const <String, Object?>{'type': 'string'},
            'ttlSeconds': const <String, Object?>{
              'type': 'integer',
              'minimum': 10,
              'maximum': 120,
            },
          },
          const <String>['leaseId', 'leaseToken', 'ttlSeconds'],
        ),
        _capacityTool(
          'lmcp.capacity.release',
          '幂等释放已预约的执行槽位',
          <String, Object?>{
            'leaseId': const <String, Object?>{'type': 'string'},
            'leaseToken': const <String, Object?>{'type': 'string'},
            'reason': const <String, Object?>{'type': 'string'},
          },
          const <String>['leaseId', 'leaseToken', 'reason'],
        ),
      ];

  static Map<String, Object?> _capacityTool(
    String name,
    String description,
    Map<String, Object?> properties,
    List<String> required,
  ) => <String, Object?>{
    'name': name,
    'title': name,
    'description': description,
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    },
    'annotations': const <String, Object?>{
      'readOnlyHint': false,
      'destructiveHint': false,
      'idempotentHint': true,
      'openWorldHint': false,
    },
    'risk': 'readOnly',
  };

  String get capabilityDigest =>
      'sha256:${sha256.convert(utf8.encode(canonicalJson(<String, Object?>{'tools': toolCatalog, 'nextCursor': null})))}';

  Future<Map<String, Object?>?> handle(
    Object? payload, {
    LmcpCallerIdentity caller = const LmcpCallerIdentity(),
  }) async {
    if (payload is! Map) return _error(null, -32600, 'Invalid Request');
    final Map<Object?, Object?> request = payload;
    final Object? id = request['id'];
    if (request['jsonrpc'] != '2.0' || request['method'] is! String) {
      return _error(id, -32600, 'Invalid Request');
    }
    final Object? rawParams = request['params'];
    if (rawParams != null && rawParams is! Map) {
      return _error(id, -32602, 'Invalid params');
    }
    final Map<String, Object?> params = rawParams == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(rawParams as Map);
    final String method = request['method']! as String;
    if (method == 'notifications/initialized') return null;
    try {
      final Object? result = switch (method) {
        'initialize' => _initialize(params),
        'ping' => <String, Object?>{},
        'tools/list' => _listTools(params),
        'tools/call' => await _callTool(params, caller),
        _ => null,
      };
      if (result == null) return _error(id, -32601, 'Method not found');
      return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
    } on LmcpProtocolException catch (error) {
      return _error(id, error.code, error.message, error.data);
    } on Object {
      return _error(id, -32603, 'Internal error');
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    if (params['protocolVersion'] != protocolVersion) {
      throw LmcpProtocolException(
        -32602,
        'Unsupported MCP protocol version',
        <String, Object?>{
          'requested': params['protocolVersion'],
          'supported': <String>[protocolVersion],
        },
      );
    }
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{'listChanged': false},
      },
      'serverInfo': <String, Object?>{
        'name': 'VibeKits',
        'version': serverVersion,
      },
    };
  }

  Map<String, Object?> _listTools(Map<String, Object?> params) {
    int offset = 0;
    final Object? cursor = params['cursor'];
    if (cursor != null && '$cursor'.isNotEmpty) {
      try {
        final String decoded = utf8.decode(
          base64Url.decode(base64Url.normalize('$cursor')),
        );
        final int separator = decoded.lastIndexOf(':');
        if (separator < 1 ||
            decoded.substring(0, separator) != catalogRevision) {
          throw const FormatException();
        }
        offset = int.parse(decoded.substring(separator + 1));
      } on Object {
        throw const LmcpProtocolException(-32602, 'Unknown tools/list cursor');
      }
    }
    if (offset < 0 || offset > toolCatalog.length) {
      throw const LmcpProtocolException(-32602, 'Unknown tools/list cursor');
    }
    final int end = (offset + pageSize).clamp(0, toolCatalog.length);
    final String? nextCursor = end < toolCatalog.length
        ? base64Url.encode(utf8.encode('$catalogRevision:$end'))
        : null;
    return <String, Object?>{
      'tools': toolCatalog.sublist(offset, end),
      'nextCursor': nextCursor,
    };
  }

  Future<Map<String, Object?>> _callTool(
    Map<String, Object?> params,
    LmcpCallerIdentity caller,
  ) async {
    final String name = params['name'] is String
        ? (params['name']! as String).trim()
        : '';
    final Object? rawArguments = params['arguments'];
    if (name.isEmpty || (rawArguments != null && rawArguments is! Map)) {
      throw const LmcpProtocolException(
        -32602,
        'tools/call requires a tool name and object arguments',
      );
    }
    final Map<String, Object?> arguments = rawArguments == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(rawArguments as Map);
    if (_capacityToolCatalog.any(
      (Map<String, Object?> entry) => entry['name'] == name,
    )) {
      return _callCapacityTool(name, arguments, caller);
    }
    final HarnessToolDefinition? tool = tools
        .where((HarnessToolDefinition candidate) => candidate.id == name)
        .firstOrNull;
    if (tool == null) {
      throw LmcpProtocolException(-32602, 'Unknown tool: $name');
    }
    validateToolArguments(arguments, tool.inputSchema);
    final Object? rawScheduling = params['scheduling'];
    if (rawScheduling != null) {
      if (rawScheduling is! Map) {
        throw const LmcpProtocolException(
          -32602,
          'scheduling must be an object',
        );
      }
      final Map<String, Object?> scheduling = Map<String, Object?>.from(
        rawScheduling,
      );
      try {
        capacityManager.validateScheduledCall(
          leaseId: '${scheduling['leaseId'] ?? ''}',
          leaseToken: '${scheduling['leaseToken'] ?? ''}',
          toolName: name,
          idempotencyKey: '${scheduling['idempotencyKey'] ?? ''}',
          callerInstanceId: caller.instanceId,
        );
      } on LmcpCapacityException catch (error) {
        throw LmcpProtocolException(-32042, error.message, <String, Object?>{
          'code': error.code,
        });
      }
    }
    final String traceId =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_traceSequence++}';
    final LmcpInboundCallHandle call = _callHub.begin(
      traceId: traceId,
      callerAppId: caller.appId,
      callerInstanceId: caller.instanceId,
      callerAddress: caller.address,
      toolId: tool.id,
      toolName: tool.name,
      arguments: arguments,
      scopeSummary: '已授权 ${tool.risk.name} · ${tool.id}',
    );
    final Future<Object> invocation =
        Future<HarnessToolCallResult>.sync(
          () => _invocationRunner(tool, arguments, call.cancellation, call),
        ).then<Object>(
          (HarnessToolCallResult result) => result,
          onError: (Object error, StackTrace stackTrace) =>
              _LmcpInvocationFailure(error, stackTrace),
        );
    final Object outcome = await Future.any<Object>(<Future<Object>>[
      invocation,
      call.cancellation.whenCancelled.then<Object>(
        (_) => const _LmcpInvocationTerminated(),
      ),
    ]);
    if (outcome is _LmcpInvocationTerminated) {
      final Map<String, Object?> terminated = <String, Object?>{
        'ok': false,
        'cancelled': true,
        'code': LmcpUserTerminatedException.code,
        'error': '调用已由本机用户强制终止',
      };
      return _toolCallResponse(
        structured: terminated,
        isError: true,
        toolName: name,
        traceId: traceId,
      );
    }
    if (outcome is _LmcpInvocationFailure) {
      call.fail();
      Error.throwWithStackTrace(outcome.error, outcome.stackTrace);
    }
    final HarnessToolCallResult result = outcome as HarnessToolCallResult;
    if (result.ok) {
      call.succeed();
    } else {
      call.fail(result.error);
    }
    final Map<String, Object?> structured = result.toJson();
    return _toolCallResponse(
      structured: structured,
      isError: !result.ok,
      toolName: name,
      traceId: traceId,
    );
  }

  Map<String, Object?> _callCapacityTool(
    String name,
    Map<String, Object?> arguments,
    LmcpCallerIdentity caller,
  ) {
    final String traceId =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_traceSequence++}';
    try {
      final Map<String, Object?> structured = switch (name) {
        'lmcp.node.status' => capacityManager.status(),
        'lmcp.capacity.reserve' => capacityManager.reserve(
          toolName: '${arguments['toolName'] ?? ''}'.trim(),
          idempotencyKey: '${arguments['idempotencyKey'] ?? ''}'.trim(),
          commanderId: '${arguments['commanderId'] ?? ''}'.trim(),
          requestedSlots: arguments['requestedSlots'] is int
              ? arguments['requestedSlots']! as int
              : 0,
          ttlSeconds: arguments['ttlSeconds'] is int
              ? arguments['ttlSeconds']! as int
              : 0,
          scopeDigest: '${arguments['scopeDigest'] ?? ''}'.trim(),
          callerInstanceId: caller.instanceId,
        ),
        'lmcp.capacity.renew' => capacityManager.renew(
          leaseId: '${arguments['leaseId'] ?? ''}'.trim(),
          leaseToken: '${arguments['leaseToken'] ?? ''}'.trim(),
          ttlSeconds: arguments['ttlSeconds'] is int
              ? arguments['ttlSeconds']! as int
              : 0,
          callerInstanceId: caller.instanceId,
        ),
        'lmcp.capacity.release' => capacityManager.release(
          leaseId: '${arguments['leaseId'] ?? ''}'.trim(),
          leaseToken: '${arguments['leaseToken'] ?? ''}'.trim(),
          callerInstanceId: caller.instanceId,
          reason: '${arguments['reason'] ?? ''}'.trim(),
        ),
        _ => throw const LmcpCapacityException(
          'UNKNOWN_CONTROL_TOOL',
          '未知容量控制工具',
        ),
      };
      return _toolCallResponse(
        structured: <String, Object?>{'ok': true, ...structured},
        isError: false,
        toolName: name,
        traceId: traceId,
      );
    } on LmcpCapacityException catch (error) {
      return _toolCallResponse(
        structured: <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': error.code,
            'message': error.message,
          },
        },
        isError: true,
        toolName: name,
        traceId: traceId,
      );
    }
  }

  Map<String, Object?> _toolCallResponse({
    required Map<String, Object?> structured,
    required bool isError,
    required String toolName,
    required String traceId,
  }) {
    return <String, Object?>{
      'content': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': jsonEncode(structured)},
      ],
      'structuredContent': structured,
      'isError': isError,
      'instanceId': instanceId,
      'toolName': toolName,
      // Backward-compatible alias for LMCP/2 clients released before the
      // engineering envelope standardized on `toolName`.
      'tool': toolName,
      'catalogRevision': catalogRevision,
      'traceId': traceId,
    };
  }

  static Map<String, Object?> _error(
    Object? id,
    int code,
    String message, [
    Object? data,
  ]) => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{'code': code, 'message': message, 'data': ?data},
  };
}

class VibekitsLmcpExposureServer {
  VibekitsLmcpExposureServer({
    required this.discovery,
    LmcpCertificateStore? certificateStore,
    LmcpCallerRequestVerifier? callerVerifier,
    this.preferredPort = 9443,
    this.path = '/mcp',
    this.maxRequestBytes = 1024 * 1024,
    this.maxConcurrentCalls = 8,
  }) : certificateStore = certificateStore ?? LmcpCertificateStore(),
       callerVerifier = callerVerifier ?? LmcpCallerRequestVerifier();

  static final VibekitsLmcpExposureServer instance = VibekitsLmcpExposureServer(
    discovery: LanPeerDiscoveryService.instance,
  );
  static const String currentAppVersion = '1.9.0-dev.147';

  final LanPeerDiscoveryService discovery;
  final LmcpCertificateStore certificateStore;
  final LmcpCallerRequestVerifier callerVerifier;
  final int preferredPort;
  final String path;
  final int maxRequestBytes;
  final int maxConcurrentCalls;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  HttpServer? _server;
  VibekitsLmcpProtocol? _protocol;
  LmcpCapacityLeaseManager? _capacityManager;
  int _activeRequests = 0;
  bool _accepting = false;

  bool get running => _server != null && _accepting;
  int? get port => _server?.port;
  Stream<bool> get changes => _changes.stream;

  Future<LmcpInstanceCertificate> prepareIdentity({
    required String displayName,
  }) => certificateStore.loadOrCreate(commonName: displayName);

  Future<void> start({
    required String instanceId,
    required String displayName,
    required String appId,
    required String appVersion,
    required String hardwareCode,
    required VibekitsHarnessToolBridge bridge,
  }) async {
    if (!discovery.running) {
      throw StateError('LMCP discovery listener must start before exposure');
    }
    if (path != '/mcp') throw const FormatException('LMCP path must be /mcp');
    final LmcpInstanceCertificate identity = await certificateStore
        .loadOrCreate(commonName: displayName);
    final SecurityContext context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final LmcpCapacityLeaseManager capacityManager = _capacityManager ??=
        LmcpCapacityLeaseManager(
          capacity: maxConcurrentCalls,
          onChanged: discovery.notifyRuntimeChanged,
        );
    capacityManager.setDraining(false);
    final VibekitsLmcpProtocol protocol = VibekitsLmcpProtocol(
      instanceId: instanceId,
      serverVersion: appVersion,
      bridge: bridge,
      capacityManager: capacityManager,
    );
    final HttpServer? currentServer = _server;
    if (currentServer != null && _accepting) {
      _protocol = protocol;
      discovery.configureLmcp2Advertisement(
        Lmcp2Advertisement(
          appId: appId,
          appVersion: appVersion,
          displayName: displayName,
          instanceId: instanceId,
          hardwareCode: hardwareCode,
          port: currentServer.port,
          path: path,
          instanceKeyFingerprint: identity.fingerprint,
          catalogRevision: protocol.catalogRevision,
          capabilityDigest: protocol.capabilityDigest,
          runtimeProvider: () => capacityManager.runtime.toJson(),
        ),
      );
      discovery.setExposureEnabled(true);
      return;
    }
    late final HttpServer server;
    try {
      server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        preferredPort,
        context,
        shared: false,
      );
    } on SocketException catch (error) {
      if (preferredPort == 0 || !_addressAlreadyInUse(error)) rethrow;
      // KEMI and VibeKits may run on the same host. LMCP/2 explicitly carries
      // the real port, and KEMI validates 1..65535 rather than requiring 9443.
      server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        0,
        context,
        shared: false,
      );
    }
    _server = server;
    _protocol = protocol;
    _accepting = true;
    server.listen(
      _handleRequest,
      onError: (_) => unawaited(stop(force: true)),
      onDone: () {
        _server = null;
        _accepting = false;
        _changes.add(false);
      },
      cancelOnError: false,
    );
    discovery.configureLmcp2Advertisement(
      Lmcp2Advertisement(
        appId: appId,
        appVersion: appVersion,
        displayName: displayName,
        instanceId: instanceId,
        hardwareCode: hardwareCode,
        port: server.port,
        path: path,
        instanceKeyFingerprint: identity.fingerprint,
        catalogRevision: protocol.catalogRevision,
        capabilityDigest: protocol.capabilityDigest,
        runtimeProvider: () => capacityManager.runtime.toJson(),
      ),
    );
    discovery.setExposureEnabled(true);
    _changes.add(true);
  }

  Future<void> stop({bool force = false}) async {
    final HttpServer? server = _server;
    _accepting = false;
    _capacityManager?.setDraining(true);
    discovery.setExposureEnabled(false);
    if (server != null) {
      try {
        await server.close(force: force).timeout(const Duration(seconds: 5));
      } on TimeoutException {
        await server.close(force: true);
      }
    }
    _server = null;
    _protocol = null;
    _capacityManager?.dispose();
    _capacityManager = null;
    discovery.configureLmcp2Advertisement(null);
    _changes.add(false);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final HttpConnectionInfo? connectionInfo = request.connectionInfo;
    if (connectionInfo == null ||
        !_privateOrLoopback(connectionInfo.remoteAddress)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (request.method != 'POST' || request.uri.path != path) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (!_accepting || _protocol == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    if (_activeRequests >= maxConcurrentCalls) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
      return;
    }
    _activeRequests++;
    try {
      final BytesBuilder body = BytesBuilder(copy: false);
      await for (final List<int> chunk in request) {
        body.add(chunk);
        if (body.length > maxRequestBytes) {
          request.response.statusCode = HttpStatus.requestEntityTooLarge;
          await request.response.close();
          return;
        }
      }
      final Uint8List requestBody = body.takeBytes();
      final LmcpVerifiedCaller verifiedCaller = callerVerifier.verify(
        headers: request.headers,
        uri: request.uri,
        body: requestBody,
      );
      final Object? decoded = jsonDecode(utf8.decode(requestBody));
      final Map<String, Object?>? response = await _protocol!.handle(
        decoded,
        caller: LmcpCallerIdentity(
          appId: verifiedCaller.appId,
          instanceId: verifiedCaller.instanceId,
          address: connectionInfo.remoteAddress.address,
        ),
      );
      request.response.headers.contentType = ContentType.json;
      if (response == null) {
        request.response.statusCode = HttpStatus.accepted;
      } else {
        final List<int> encoded = utf8.encode(jsonEncode(response));
        if (encoded.length > maxRequestBytes) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': response['id'],
              'error': <String, Object?>{
                'code': -32603,
                'message': 'MCP response exceeded the 1 MiB safety limit',
              },
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(encoded);
        }
      }
    } on LmcpCallerAuthException catch (error) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': null,
          'error': <String, Object?>{
            'code': -32001,
            'message': 'Caller identity verification failed',
            'data': <String, Object?>{'code': error.code},
          },
        }),
      );
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': null,
          'error': <String, Object?>{'code': -32700, 'message': 'Parse error'},
        }),
      );
    } on Object {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': null,
          'error': <String, Object?>{
            'code': -32603,
            'message': 'Internal error',
          },
        }),
      );
    } finally {
      _activeRequests--;
      try {
        await request.response.close();
      } on Object {
        // The caller may disconnect while waiting for local approval.
      }
    }
  }

  static bool _privateOrLoopback(InternetAddress address) {
    if (address.isLoopback) return true;
    if (address.type != InternetAddressType.IPv4) return false;
    final Uint8List bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static bool _addressAlreadyInUse(SocketException error) {
    final String message = '$error ${error.osError}'.toLowerCase();
    return const <int>{48, 98, 10048}.contains(error.osError?.errorCode) ||
        message.contains('address already in use') ||
        message.contains('binding multiple times') ||
        message.contains('shared flag');
  }
}

void validateToolArguments(
  Map<String, Object?> arguments,
  Map<String, Object?> schema,
) {
  if (schema['type'] != 'object') {
    throw const LmcpProtocolException(
      -32602,
      'Tool inputSchema must describe an object',
    );
  }
  _validateJsonValue(arguments, schema, 'arguments', 0);
}

void _validateJsonValue(
  Object? value,
  Map<String, Object?> schema,
  String path,
  int depth,
) {
  if (depth > 16) {
    throw const LmcpProtocolException(-32602, 'Tool arguments are too deep');
  }
  final Object? type = schema['type'];
  if (!_matchesJsonType(value, type)) {
    throw LmcpProtocolException(
      -32602,
      'Invalid type for tool argument: $path',
      <String, Object?>{'expected': type},
    );
  }
  if (schema['enum'] case final List<Object?> allowed) {
    if (!allowed.contains(value)) {
      throw LmcpProtocolException(
        -32602,
        'Invalid value for tool argument: $path',
        <String, Object?>{'allowed': allowed},
      );
    }
  }
  if (value is String) {
    final int? minimum = (schema['minLength'] as num?)?.toInt();
    final int? maximum = (schema['maxLength'] as num?)?.toInt();
    final String? pattern = schema['pattern'] is String
        ? schema['pattern']! as String
        : null;
    if (minimum != null && value.length < minimum ||
        maximum != null && value.length > maximum ||
        pattern != null && !RegExp(pattern).hasMatch(value)) {
      throw LmcpProtocolException(
        -32602,
        'Invalid string value for tool argument: $path',
      );
    }
    return;
  }
  if (value is num) {
    final num? minimum = schema['minimum'] as num?;
    final num? maximum = schema['maximum'] as num?;
    if (minimum != null && value < minimum ||
        maximum != null && value > maximum) {
      throw LmcpProtocolException(
        -32602,
        'Tool argument is outside the allowed range: $path',
      );
    }
    return;
  }
  if (value is List) {
    final int? minimum = (schema['minItems'] as num?)?.toInt();
    final int? maximum = (schema['maxItems'] as num?)?.toInt();
    if (minimum != null && value.length < minimum ||
        maximum != null && value.length > maximum) {
      throw LmcpProtocolException(
        -32602,
        'Invalid item count for tool argument: $path',
      );
    }
    if (schema['items'] case final Map<Object?, Object?> itemSchema) {
      final Map<String, Object?> normalized = Map<String, Object?>.from(
        itemSchema,
      );
      for (int index = 0; index < value.length; index++) {
        _validateJsonValue(
          value[index],
          normalized,
          '$path[$index]',
          depth + 1,
        );
      }
    }
    return;
  }
  if (value is! Map) return;
  if (schema['type'] != 'object') return;
  if (value.keys.any((Object? key) => key is! String)) {
    throw const LmcpProtocolException(
      -32602,
      'Tool argument objects require string keys',
    );
  }
  final Map<String, Object?> object = Map<String, Object?>.from(value);
  final Map<String, Object?> properties = schema['properties'] is Map
      ? Map<String, Object?>.from(schema['properties']! as Map)
      : const <String, Object?>{};
  final Set<String> required = schema['required'] is List
      ? (schema['required']! as List).whereType<String>().toSet()
      : const <String>{};
  final List<String> missing = required
      .where((String key) => !object.containsKey(key))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw LmcpProtocolException(
      -32602,
      'Missing required tool arguments',
      <String, Object?>{'fields': missing},
    );
  }
  final Object? additional = schema['additionalProperties'];
  if (additional == false) {
    final List<String> unknown = object.keys
        .where((String key) => !properties.containsKey(key))
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      throw LmcpProtocolException(
        -32602,
        'Unknown tool arguments',
        <String, Object?>{'fields': unknown},
      );
    }
  }
  for (final MapEntry<String, Object?> entry in object.entries) {
    final Object? rawProperty = properties[entry.key];
    final Object? selected = rawProperty ?? additional;
    if (selected is! Map) continue;
    _validateJsonValue(
      entry.value,
      Map<String, Object?>.from(selected),
      '$path.${entry.key}',
      depth + 1,
    );
  }
}

bool _matchesJsonType(Object? value, Object? type) => switch (type) {
  null => true,
  'null' => value == null,
  'string' => value is String,
  'boolean' => value is bool,
  'integer' => value is int,
  'number' => value is num,
  'object' => value is Map,
  'array' => value is List,
  _ => false,
};

String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalize(value[key]),
    };
  }
  return value;
}
