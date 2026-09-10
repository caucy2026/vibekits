import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class HarnessRemoteApiAdapter {
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  });

  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  });

  /// Complete authoritative Workspace projection. The official DSH API owns
  /// this as the opening frame of `workspace/follow`, not as a unary method.
  Future<List<Map<String, dynamic>>> workspaceSnapshot();

  Future<void> close();
}

/// Execution-side carrier for the official DSH API. Never expose this object
/// directly to a network listener: authenticated, scoped dispatch owns access.
/// Remote URLs are deliberately rejected to prevent SSRF and credential leaks.
class HarnessOfficialRemoteAdapter implements HarnessRemoteApiAdapter {
  // Official Harness may append a browser-only token to its announced URL.
  // Validate the socket origin and keep that token private. It is forwarded
  // only to the same loopback API; the public endpoint stays canonical so the
  // credential is neither rendered nor logged by callers.
  HarnessOfficialRemoteAdapter(Uri endpoint)
    : endpoint = Uri(scheme: 'http', host: '127.0.0.1', port: endpoint.port),
      _token = _validatedToken(endpoint) {
    if (endpoint.scheme != 'http' ||
        !const {'127.0.0.1', 'localhost'}.contains(endpoint.host) ||
        endpoint.port <= 0 ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty && endpoint.path != '/')) {
      throw ArgumentError(
        'Expected an execution-side loopback DSH endpoint '
        '(scheme=${endpoint.scheme}, host=${endpoint.host}, '
        'port=${endpoint.port}, userInfo=${endpoint.userInfo.isNotEmpty}, '
        'fragment=${endpoint.hasFragment}, '
        'path=${endpoint.path})',
      );
    }
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri endpoint;
  final String? _token;
  final HttpClient _http = HttpClient();
  final Set<WebSocket> _sockets = {};
  Future<void>? _authentication;
  String? _cookieHeader;
  bool _closed = false;
  static const maxFrameBytes = 8 * 1024 * 1024;
  static const _streamMuxPath = '/api/remote.mux';

  static String? _validatedToken(Uri endpoint) {
    if (!endpoint.hasQuery) return null;
    final values = endpoint.queryParametersAll;
    if (values.length != 1 ||
        !values.containsKey('token') ||
        values['token']!.length != 1 ||
        values['token']!.single.isEmpty ||
        values['token']!.single.length > 4096) {
      throw const FormatException('Invalid official Harness URL query');
    }
    return values['token']!.single;
  }

  Uri _apiUri(
    String path, {
    String? scheme,
    bool includeBootstrapToken = false,
  }) => endpoint.replace(
    scheme: scheme,
    path: path,
    queryParameters: includeBootstrapToken && _token != null
        ? <String, String>{'token': _token}
        : null,
  );

  Future<void> _ensureAuthenticated() async {
    if (_token == null || _cookieHeader != null) return;
    final pending = _authentication;
    if (pending != null) return pending;
    final future = _exchangeToken();
    _authentication = future;
    try {
      await future;
    } finally {
      if (identical(_authentication, future)) _authentication = null;
    }
  }

  Future<void> _exchangeToken() async {
    if (_closed) throw StateError('REMOTE_ADAPTER_CLOSED');
    final request = await _http.getUrl(
      _apiUri('/', includeBootstrapToken: true),
    );
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();
    final cookies = response.cookies;
    if (response.statusCode < 200 ||
        response.statusCode >= 400 ||
        cookies.isEmpty) {
      throw HttpException('Official DSH token exchange ${response.statusCode}');
    }
    final value = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    if (value.isEmpty ||
        value.length > 8192 ||
        value.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Invalid official DSH session cookie');
    }
    _cookieHeader = value;
  }

  void _authorize(HttpHeaders headers) {
    final cookie = _cookieHeader;
    if (cookie != null) headers.set(HttpHeaders.cookieHeader, cookie);
  }

  /// Keep official request/response envelopes intact; rpcId is correlation,
  /// not a promise of deduplication. The outer command ledger provides that.
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closed) throw StateError('REMOTE_ADAPTER_CLOSED');
    final method = envelope['method'];
    final rpcId = envelope['rpcId'];
    if (envelope['type'] != 'client-request' ||
        rpcId is! String ||
        rpcId.isEmpty ||
        method is! String ||
        !RegExp(
          r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$',
        ).hasMatch(method) ||
        envelope['payload'] is! Map) {
      throw const FormatException('Invalid official client-request');
    }
    final target = _officialInvocation(method, envelope['payload'] as Map);
    final officialEnvelope = <String, dynamic>{
      'type': 'client-request',
      'rpcId': rpcId,
      'method': target.endpoint,
      'payload': target.payload,
    };
    return _post(
      '/api/${target.endpoint}',
      officialEnvelope,
      timeout: timeout,
      rpcId: rpcId,
    );
  }

  _OfficialInvocation _officialInvocation(String method, Map payload) {
    final request = Map<String, dynamic>.from(payload);
    switch (method) {
      case 'session.models':
        return const _OfficialInvocation('session/modelCatalog', {
          'args': <String, Object?>{},
        });
      case 'session.history':
        // History is stream-backed in current DSH and is handled separately
        // by the remote UI before command forwarding is enabled.
        throw UnsupportedError('REMOTE_HISTORY_REQUIRES_SESSION_STREAM');
      case 'session.selectModel':
        return _OfficialInvocation('session/selectModel', {
          'args': {'request': request},
        });
      case 'session.rename':
        return _OfficialInvocation('session/rename', {
          'args': {'request': request},
        });
      case 'session.prompt':
        final text = request.remove('text');
        if (text is! String || text.trim().isEmpty) {
          throw const FormatException('Invalid official Harness prompt');
        }
        return _OfficialInvocation('session/prompt', {
          'args': {
            'request': {
              ...request,
              'requestId': request['requestId'] ?? _randomId(),
              'mode': request['mode'] ?? 'queue',
              'content': [
                {'type': 'text', 'text': text},
              ],
            },
          },
        });
      case 'session.updateQueue':
        return _OfficialInvocation('session/updateQueue', {
          'args': {'request': request},
        });
      case 'session.cancel':
        return _OfficialInvocation('session/cancel', {
          'args': {'request': request},
        });
      default:
        throw UnsupportedError('REMOTE_OFFICIAL_METHOD_UNSUPPORTED');
    }
  }

  static String _randomId() =>
      '${DateTime.now().microsecondsSinceEpoch}-remote';

  /// Approval replies retain their original server request identity. The
  /// dispatch layer must verify ownership and scope before forwarding them.
  Future<Map<String, dynamic>> respond(Map<String, dynamic> envelope) {
    if (envelope['type'] != 'client-response' ||
        envelope['rpcId'] is! String ||
        (envelope['rpcId'] as String).isEmpty ||
        envelope['result'] is! Map) {
      throw const FormatException('Invalid official client-response');
    }
    return _post('/api/respond', envelope);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
    String? rpcId,
  }) async {
    if (_closed) throw StateError('REMOTE_ADAPTER_CLOSED');
    final bytes = utf8.encode(jsonEncode(envelope));
    if (bytes.length > maxFrameBytes) {
      throw const FormatException('Official request exceeds frame limit');
    }
    HttpClientRequest? pending;
    var timedOut = false;
    Future<Map<String, dynamic>> send() async {
      await _ensureAuthenticated();
      final request = await _http.postUrl(_apiUri(path));
      pending = request;
      if (_closed || timedOut) {
        request.abort();
        throw StateError('REMOTE_ADAPTER_REQUEST_ABORTED');
      }
      request.followRedirects = false;
      _authorize(request.headers);
      request.headers.contentType = ContentType.json;
      request.add(bytes);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('Official DSH HTTP ${response.statusCode}');
      }
      final output = <int>[];
      await for (final chunk in response) {
        if (output.length + chunk.length > maxFrameBytes) {
          request.abort();
          throw const FormatException('Official response exceeds frame limit');
        }
        output.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(output));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid official response');
      }
      if (rpcId != null &&
          (decoded['type'] != 'server-response' ||
              decoded['rpcId'] != rpcId ||
              decoded['result'] is! Map)) {
        throw const FormatException('Official response identity mismatch');
      }
      return decoded;
    }

    // Timeout is an unknown outcome, never automatic replay or task stop.
    return send().timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        pending?.abort();
        throw TimeoutException('REMOTE_OUTCOME_UNKNOWN', timeout);
      },
    );
  }

  /// WebSocket is a downlink only in official DSH; command traffic uses HTTP.
  /// No reconnect here: the session owner must resnapshot before resuming UI.
  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) async* {
    if (_closed) throw StateError('REMOTE_ADAPTER_CLOSED');
    onConnected?.call();
    await for (final value in _openStream('\$events', const {'args': {}})) {
      if (value['type'] != 'emit' || value['event'] is! String) continue;
      final args = value['args'];
      if (args is! List || args.isEmpty || args.first is! String) continue;
      yield <String, dynamic>{
        'type': 'server-request',
        'rpcId': 'event-${DateTime.now().microsecondsSinceEpoch}',
        'method': value['event'],
        'payload': <String, dynamic>{'sessionId': args.first, 'args': args},
      };
    }
  }

  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async {
    await for (final frame in _openStream('workspace/follow', const {
      'args': <String, Object?>{},
    })) {
      if (frame['type'] != 'baseline' || frame['value'] is! Map) {
        throw const FormatException('Invalid official Workspace baseline');
      }
      final items = (frame['value'] as Map)['items'];
      if (items is! List) {
        throw const FormatException('Invalid official Workspace inventory');
      }
      return [
        for (final item in items)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    throw StateError('REMOTE_INVENTORY_UNAVAILABLE');
  }

  Stream<Map<String, dynamic>> _openStream(
    String endpointName,
    Map<String, Object?> payload,
  ) async* {
    await _ensureAuthenticated();
    final socket = await WebSocket.connect(
      _apiUri(_streamMuxPath, scheme: 'ws').toString(),
      headers: _cookieHeader == null
          ? null
          : <String, dynamic>{HttpHeaders.cookieHeader: _cookieHeader},
      customClient: _http,
    );
    if (_closed) {
      await socket.close();
      throw StateError('REMOTE_ADAPTER_CLOSED');
    }
    _sockets.add(socket);
    socket.pingInterval = const Duration(seconds: 20);
    final streamId = _randomId();
    socket.add(
      jsonEncode({
        'type': 'open',
        'streamId': streamId,
        'endpoint': endpointName,
        'payload': payload,
      }),
    );
    try {
      await for (final raw in socket) {
        if (raw is! String || utf8.encode(raw).length > maxFrameBytes) {
          throw const FormatException('Invalid official stream frame');
        }
        final frame = jsonDecode(raw);
        if (frame is! Map<String, dynamic> ||
            frame['streamId'] != streamId ||
            frame['type'] is! String) {
          throw const FormatException('Invalid official stream envelope');
        }
        switch (frame['type']) {
          case 'item':
            if (frame['value'] is! Map) {
              throw const FormatException('Invalid official stream item');
            }
            yield Map<String, dynamic>.from(frame['value'] as Map);
          case 'end':
            return;
          case 'error':
            throw StateError('REMOTE_OFFICIAL_STREAM_ERROR');
          default:
            throw const FormatException('Unknown official stream frame');
        }
      }
    } finally {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode({'type': 'cancel', 'streamId': streamId}));
      }
      _sockets.remove(socket);
      await socket.close();
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _http.close(force: true);
    await Future.wait(_sockets.toList().map((socket) => socket.close()));
    _sockets.clear();
  }
}

final class _OfficialInvocation {
  const _OfficialInvocation(this.endpoint, this.payload);
  final String endpoint;
  final Map<String, Object?> payload;
}
