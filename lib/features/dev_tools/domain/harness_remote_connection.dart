import 'dart:async';
import 'dart:convert';

/// An authenticated, encrypted connection supplied by the native direct/relay
/// transport. Implementations must verify the Harness product identity before
/// exposing frames; a peerId declared in an incoming frame is never trusted.
abstract interface class HarnessRemoteChannel {
  String get authenticatedPeerId;
  Stream<String> get frames;
  Future<void> send(String frame);
  Future<void> close();
}

enum HarnessRemoteConnectionState { connected, disconnected, closed }

/// Correlates responses without conflating task execution with socket state.
/// A lost command reply means outcome unknown; reconnect never resends it here.
class HarnessRemoteConnection {
  HarnessRemoteConnection(this.channel) {
    if (channel.authenticatedPeerId.isEmpty) {
      throw ArgumentError('Remote channel is not authenticated');
    }
    _subscription = channel.frames.listen(
      _receive,
      onError: (Object error, StackTrace stack) => _disconnect(error),
      onDone: () => _disconnect(StateError('REMOTE_DISCONNECTED')),
    );
  }
  final HarnessRemoteChannel channel;
  late final StreamSubscription<String> _subscription;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _states = StreamController<HarnessRemoteConnectionState>.broadcast();
  HarnessRemoteConnectionState _state = HarnessRemoteConnectionState.connected;
  HarnessRemoteConnectionState get state => _state;
  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<HarnessRemoteConnectionState> get states => _states.stream;

  Future<Map<String, dynamic>> request(
    String requestId,
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_state != HarnessRemoteConnectionState.connected) {
      throw StateError('REMOTE_DISCONNECTED');
    }
    if (requestId.isEmpty || _pending.containsKey(requestId)) {
      throw StateError('REMOTE_REQUEST_ID_CONFLICT');
    }
    if (_pending.length >= 128) throw StateError('REMOTE_BACKPRESSURE');
    final frame = jsonEncode({
      'protocol': 'vibekits.harness.remote',
      'version': 1,
      'type': 'request',
      'requestId': requestId,
      'payload': payload,
    });
    if (utf8.encode(frame).length > 8 * 1024 * 1024) {
      throw const FormatException('Remote frame exceeds limit');
    }
    final completion = Completer<Map<String, dynamic>>();
    _pending[requestId] = completion;
    // Attach the timeout/error listener before asynchronous transport work.
    final result = completion.future.timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException('REMOTE_OUTCOME_UNKNOWN', timeout);
      },
    );
    unawaited(
      channel.send(frame).catchError((Object error, StackTrace stack) {
        if (!completion.isCompleted) completion.completeError(error, stack);
      }),
    );
    try {
      return await result;
    } finally {
      _pending.remove(requestId);
    }
  }

  void _receive(String frame) {
    if (_state != HarnessRemoteConnectionState.connected) return;
    try {
      if (utf8.encode(frame).length > 8 * 1024 * 1024) {
        throw const FormatException('Remote frame exceeds limit');
      }
      final value = jsonDecode(frame);
      if (value is! Map<String, dynamic> ||
          value['protocol'] != 'vibekits.harness.remote' ||
          value['version'] != 1 ||
          value['payload'] is! Map<String, dynamic>) {
        throw const FormatException('Remote protocol mismatch');
      }
      if (value['type'] == 'response') {
        final completion = _pending[value['requestId']];
        if (completion != null && !completion.isCompleted) {
          completion.complete(value['payload'] as Map<String, dynamic>);
        }
      } else if (value['type'] == 'event') {
        _events.add(value['payload'] as Map<String, dynamic>);
      } else {
        throw const FormatException('Unexpected remote frame type');
      }
    } catch (error) {
      _disconnect(error);
      unawaited(channel.close());
    }
  }

  void _disconnect(Object error) {
    if (_state != HarnessRemoteConnectionState.connected) return;
    _state = HarnessRemoteConnectionState.disconnected;
    _states.add(_state);
    for (final completion in _pending.values) {
      if (!completion.isCompleted) {
        completion.completeError(StateError('REMOTE_OUTCOME_UNKNOWN: $error'));
      }
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_state == HarnessRemoteConnectionState.closed) return;
    _disconnect(StateError('REMOTE_CONNECTION_CLOSED'));
    _state = HarnessRemoteConnectionState.closed;
    _states.add(_state);
    await _subscription.cancel();
    await channel.close();
    await _events.close();
    await _states.close();
  }
}
