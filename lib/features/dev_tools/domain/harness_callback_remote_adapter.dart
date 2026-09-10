import 'dart:async';

import 'harness_official_remote_adapter.dart';

typedef HarnessRemoteRequestHandler =
    Future<Map<String, Object?>> Function(
      String method,
      Map<String, dynamic> payload,
    );

/// Adapts an in-process Harness implementation to the same request and event
/// contract used by the official loopback HTTP bridge. Mobile therefore keeps
/// one authoritative conversation state machine instead of a shadow backend.
final class HarnessCallbackRemoteAdapter implements HarnessRemoteApiAdapter {
  HarnessCallbackRemoteAdapter(this._handler);

  final HarnessRemoteRequestHandler _handler;
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _closed = false;

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closed) throw StateError('REMOTE_ADAPTER_CLOSED');
    final Object? rpcId = envelope['rpcId'];
    final Object? method = envelope['method'];
    final Object? payload = envelope['payload'];
    if (envelope['type'] != 'client-request' ||
        rpcId is! String ||
        rpcId.isEmpty ||
        method is! String ||
        payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid callback remote request');
    }
    final Map<String, Object?> result = await _handler(
      method,
      payload,
    ).timeout(timeout);
    return <String, dynamic>{
      'type': 'server-response',
      'rpcId': rpcId,
      'result': Map<String, dynamic>.from(result),
    };
  }

  void publish(Map<String, dynamic> payload) {
    if (!_closed) _events.add(Map<String, dynamic>.unmodifiable(payload));
  }

  @override
  Future<List<Map<String, dynamic>>> workspaceSnapshot() async {
    final result = await _handler('workspace.list', <String, dynamic>{});
    final value = result['value'];
    final items = value is Map ? value['items'] : null;
    if (result['ok'] != true || items is! List) {
      throw StateError('REMOTE_INVENTORY_UNAVAILABLE');
    }
    return [
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  @override
  Stream<Map<String, dynamic>> events({
    bool host = false,
    void Function()? onConnected,
  }) async* {
    if (_closed) throw StateError('REMOTE_ADAPTER_CLOSED');
    onConnected?.call();
    yield* _events.stream;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _events.close();
  }
}
