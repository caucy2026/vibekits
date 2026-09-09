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

  Future<void> close();
}

/// Execution-side carrier for the official DSH API. Never expose this object
/// directly to a network listener: authenticated, scoped dispatch owns access.
/// Remote URLs are deliberately rejected to prevent SSRF and credential leaks.
class HarnessOfficialRemoteAdapter implements HarnessRemoteApiAdapter {
  HarnessOfficialRemoteAdapter(this.endpoint) {
    if (endpoint.scheme != 'http' ||
        endpoint.host != '127.0.0.1' ||
        endpoint.port <= 0 ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty && endpoint.path != '/')) {
      throw ArgumentError('Expected an execution-side loopback DSH endpoint');
    }
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri endpoint;
  final HttpClient _http = HttpClient();
  final Set<WebSocket> _sockets = {};
  bool _closed = false;
  static const maxFrameBytes = 8 * 1024 * 1024;

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
    return _post('/api/$method', envelope, timeout: timeout, rpcId: rpcId);
  }

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
      final request = await _http.postUrl(endpoint.resolve(path));
      pending = request;
      if (_closed || timedOut) {
        request.abort();
        throw StateError('REMOTE_ADAPTER_REQUEST_ABORTED');
      }
      request.followRedirects = false;
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
    final uri = endpoint.replace(
      scheme: 'ws',
      path: host ? '/api/events.host' : '/api/events.mux',
    );
    final socket = await WebSocket.connect(uri.toString(), customClient: _http);
    if (_closed) {
      await socket.close();
      throw StateError('REMOTE_ADAPTER_CLOSED');
    }
    _sockets.add(socket);
    socket.pingInterval = const Duration(seconds: 20);
    try {
      onConnected?.call();
      await for (final frame in socket) {
        if (frame is! String || utf8.encode(frame).length > maxFrameBytes) {
          throw const FormatException('Invalid official event frame');
        }
        final value = jsonDecode(frame);
        if (value is! Map<String, dynamic> ||
            value['type'] != 'server-request' ||
            value['rpcId'] is! String ||
            value['payload'] is! Map) {
          throw const FormatException('Invalid official event envelope');
        }
        yield value;
      }
    } finally {
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
