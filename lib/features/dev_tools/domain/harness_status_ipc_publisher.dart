import 'dart:async';

import 'harness_status_ipc_protocol.dart';
import 'harness_status_ipc_transport.dart';

typedef HarnessStatusSnapshotProvider =
    FutureOr<Map<String, Object?>> Function();
typedef HarnessStatusSnapshotStream = Stream<Map<String, Object?>> Function();
typedef HarnessStatusIpcObserver = void Function(HarnessStatusIpcEvent event);

enum HarnessStatusIpcEventType {
  handshakeSucceeded,
  subscriptionStarted,
  heartbeatSent,
  unsubscribed,
  disconnected,
}

class HarnessStatusIpcEvent {
  const HarnessStatusIpcEvent({
    required this.type,
    required this.peerId,
    required this.streamSequence,
    required this.occurredAt,
  });

  final HarnessStatusIpcEventType type;
  final String peerId;
  final int streamSequence;
  final DateTime occurredAt;
}

class HarnessStatusIpcStartResult {
  const HarnessStatusIpcStartResult._({
    required this.available,
    required this.endpoint,
    required this.reason,
  });

  const HarnessStatusIpcStartResult.available(String endpoint)
    : this._(available: true, endpoint: endpoint, reason: '');

  const HarnessStatusIpcStartResult.unavailable(String reason)
    : this._(available: false, endpoint: '', reason: reason);

  final bool available;
  final String endpoint;
  final String reason;
}

/// Fail-isolated, read-only local publisher consumed by the local RustDesk
/// Host. The publisher never initiates a RustDesk or network connection.
class HarnessStatusIpcPublisher {
  HarnessStatusIpcPublisher({
    required this.snapshotProvider,
    required this.snapshotStream,
    required this.publisherVersion,
    HarnessStatusIpcTransport? transport,
    this.maxConnections = 4,
    this.maxSubscriptions = 1,
    this.handshakeTimeout = const Duration(seconds: 3),
    this.busyHeartbeat = harnessStatusBusyHeartbeat,
    this.idleHeartbeat = harnessStatusIdleHeartbeat,
    this.observer,
    String? instanceId,
  }) : transport = transport ?? HarnessStatusIpcTransports.platformDefault(),
       instanceId = instanceId ?? _ephemeralInstanceId();

  final HarnessStatusSnapshotProvider snapshotProvider;
  final HarnessStatusSnapshotStream snapshotStream;
  final String publisherVersion;
  final HarnessStatusIpcTransport transport;
  final int maxConnections;
  final int maxSubscriptions;
  final Duration handshakeTimeout;
  final Duration busyHeartbeat;
  final Duration idleHeartbeat;
  final HarnessStatusIpcObserver? observer;
  final String instanceId;

  HarnessStatusIpcListener? _listener;
  StreamSubscription<HarnessStatusIpcConnection>? _listenerSubscription;
  final Set<_HarnessStatusClient> _clients = <_HarnessStatusClient>{};
  int _activeSubscriptions = 0;
  bool _stopping = false;

  String get endpoint => _listener?.endpoint ?? '';
  bool get isAvailable => _listener != null;
  int get activeConnectionCount => _clients.length;
  int get activeSubscriptionCount => _activeSubscriptions;

  Future<HarnessStatusIpcStartResult> start() async {
    if (_listener != null) {
      return HarnessStatusIpcStartResult.available(endpoint);
    }
    _stopping = false;
    try {
      final HarnessStatusIpcListener listener = await transport.bind();
      _listener = listener;
      _listenerSubscription = listener.connections.listen(
        (HarnessStatusIpcConnection connection) {
          unawaited(_accept(listener, connection));
        },
        onError: (Object _, StackTrace _) {
          // A failed accept is isolated from Harness and existing clients.
        },
      );
      return HarnessStatusIpcStartResult.available(listener.endpoint);
    } on HarnessStatusTransportUnavailable catch (error) {
      return HarnessStatusIpcStartResult.unavailable(error.reason);
    } on Object {
      return const HarnessStatusIpcStartResult.unavailable(
        'Harness status IPC failed to start',
      );
    }
  }

  Future<void> _accept(
    HarnessStatusIpcListener listener,
    HarnessStatusIpcConnection connection,
  ) async {
    if (_stopping || _clients.length >= maxConnections) {
      connection.destroy();
      return;
    }
    if (connection.peerIdentity == null ||
        connection.peerIdentity != listener.localIdentity) {
      final _LatestWinsFrameWriter writer = _LatestWinsFrameWriter(connection);
      writer.enqueueCritical(_error('unauthorized_peer'));
      await writer.closeWhenDrained();
      return;
    }
    late final _HarnessStatusClient client;
    client = _HarnessStatusClient(
      connection: connection,
      publisher: this,
      onClosed: () {
        _clients.remove(client);
      },
    );
    _clients.add(client);
    client.start();
  }

  bool _tryAcquireSubscription() {
    if (_activeSubscriptions >= maxSubscriptions) return false;
    _activeSubscriptions += 1;
    return true;
  }

  void _releaseSubscription() {
    if (_activeSubscriptions > 0) _activeSubscriptions -= 1;
  }

  void _notify(
    HarnessStatusIpcEventType type, {
    required String peerId,
    required int streamSequence,
  }) {
    final HarnessStatusIpcObserver? callback = observer;
    if (callback == null) return;
    try {
      callback(
        HarnessStatusIpcEvent(
          type: type,
          peerId: peerId,
          streamSequence: streamSequence,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    } on Object {
      // UI/telemetry observers are never allowed to affect IPC or Harness.
    }
  }

  Future<void> stop() async {
    _stopping = true;
    await _listenerSubscription?.cancel();
    _listenerSubscription = null;
    final List<_HarnessStatusClient> clients = _clients.toList();
    for (final _HarnessStatusClient client in clients) {
      await client.close();
    }
    _clients.clear();
    _activeSubscriptions = 0;
    final HarnessStatusIpcListener? listener = _listener;
    _listener = null;
    await listener?.close();
  }

  static Map<String, Object?> _error(String code) => <String, Object?>{
    'type': 'error',
    'code': harnessStatusErrorCodes.contains(code) ? code : 'internal_error',
    'message': _errorMessage(code),
  };

  static String _errorMessage(String code) => switch (code) {
    'invalid_frame' => 'Invalid status frame',
    'frame_too_large' => 'Status frame exceeds the negotiated limit',
    'invalid_handshake' => 'Invalid Harness status handshake',
    'unsupported_version' => 'No compatible Harness status version',
    'unauthorized_peer' => 'Local peer identity was rejected',
    'not_subscribed' => 'No active Harness status subscription',
    'subscription_busy' => 'Another Harness status subscription is active',
    _ => 'Harness status request failed',
  };

  static String _ephemeralInstanceId() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    final int mixed = Object().hashCode ^ now;
    return '${now.toRadixString(16)}-${mixed.toUnsigned(32).toRadixString(16)}';
  }
}

class _HarnessStatusClient {
  _HarnessStatusClient({
    required this.connection,
    required this.publisher,
    required this.onClosed,
  }) : _writer = _LatestWinsFrameWriter(connection),
       _decoder = HarnessStatusFrameDecoder();

  final HarnessStatusIpcConnection connection;
  final HarnessStatusIpcPublisher publisher;
  final void Function() onClosed;
  final _LatestWinsFrameWriter _writer;
  final HarnessStatusFrameDecoder _decoder;

  StreamSubscription<List<int>>? _inputSubscription;
  StreamSubscription<Map<String, Object?>>? _statusSubscription;
  Timer? _handshakeTimer;
  Timer? _heartbeatTimer;
  Future<void> _incoming = Future<void>.value();
  bool _handshaken = false;
  bool _subscribed = false;
  bool _closed = false;
  int _negotiatedMaxFrame = harnessStatusMaxFrameBytes;
  String _peerId = '';
  int _latestSequence = 0;
  bool _busy = false;

  void start() {
    _handshakeTimer = Timer(publisher.handshakeTimeout, () {
      unawaited(_fatal('invalid_handshake'));
    });
    _inputSubscription = connection.input.listen(
      _receive,
      onError: (Object _, StackTrace _) {
        unawaited(close());
      },
      onDone: () {
        unawaited(close());
      },
      cancelOnError: true,
    );
  }

  void _receive(List<int> bytes) {
    if (_closed) return;
    late final List<Map<String, Object?>> frames;
    try {
      frames = _decoder.add(bytes);
    } on HarnessStatusFrameException catch (error) {
      unawaited(_fatal(error.code));
      return;
    } on Object {
      unawaited(_fatal('invalid_frame'));
      return;
    }
    for (final Map<String, Object?> frame in frames) {
      _incoming = _incoming.then((_) => _handle(frame)).catchError((Object _) {
        return _fatal('internal_error');
      });
    }
  }

  Future<void> _handle(Map<String, Object?> frame) async {
    if (_closed) return;
    final Object? type = frame['type'];
    if (!_handshaken) {
      if (type != 'hello') {
        await _fatal('invalid_handshake');
        return;
      }
      await _hello(frame);
      return;
    }
    switch (type) {
      case 'getSnapshot':
        await _sendCurrentSnapshot(full: true);
      case 'subscribe':
        await _subscribe(frame);
      case 'resync':
        if (!_subscribed) {
          _writer.enqueueCritical(
            HarnessStatusIpcPublisher._error('not_subscribed'),
          );
          return;
        }
        await _sendCurrentSnapshot(full: true);
      case 'unsubscribe':
        await _unsubscribe();
      default:
        await _fatal('invalid_frame');
    }
  }

  Future<void> _hello(Map<String, Object?> frame) async {
    final Object? versionsValue = frame['versions'];
    final List<int> versions = versionsValue is List
        ? versionsValue.whereType<int>().toList()
        : const <int>[];
    final Object? clientValue = frame['client'];
    if (frame['protocol'] != harnessStatusProtocol ||
        versionsValue is! List ||
        versions.length != versionsValue.length ||
        clientValue is! String ||
        !const <String>{'rustdesk', 'kemi-rustdesk'}.contains(clientValue) ||
        !_validPeerId(frame['peerId']) ||
        !_validNonce(frame['nonce'])) {
      await _fatal('invalid_handshake');
      return;
    }
    if (!versions.contains(harnessStatusProtocolVersion)) {
      await _fatal('unsupported_version');
      return;
    }
    final Object? requestedMaxValue = frame['maxFrameBytes'];
    if (requestedMaxValue is! int || requestedMaxValue < 512) {
      await _fatal('invalid_handshake');
      return;
    }
    _peerId = frame['peerId']! as String;
    _negotiatedMaxFrame = requestedMaxValue < harnessStatusMaxFrameBytes
        ? requestedMaxValue
        : harnessStatusMaxFrameBytes;
    _decoder.maxFrameBytes = _negotiatedMaxFrame;
    _writer.maxFrameBytes = _negotiatedMaxFrame;
    _handshaken = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _writer.enqueueCritical(<String, Object?>{
      'type': 'helloAck',
      'protocol': harnessStatusProtocol,
      'selectedVersion': harnessStatusProtocolVersion,
      'publisher': 'vibekits',
      'publisherVersion': publisher.publisherVersion,
      'instanceId': publisher.instanceId,
      'capabilities': const <String>[
        'snapshot',
        'subscribe',
        'heartbeat',
        'resync',
      ],
      'nonce': frame['nonce'],
      'maxFrameBytes': _negotiatedMaxFrame,
    });
    publisher._notify(
      HarnessStatusIpcEventType.handshakeSucceeded,
      peerId: _peerId,
      streamSequence: _latestSequence,
    );
  }

  bool _validPeerId(Object? value) =>
      value is String && RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value);

  bool _validNonce(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 256;

  Future<void> _subscribe(Map<String, Object?> frame) async {
    final Object? after = frame['afterStreamSequence'];
    if (after != null && (after is! int || after < 0)) {
      await _fatal('invalid_frame');
      return;
    }
    if (!_subscribed) {
      if (!publisher._tryAcquireSubscription()) {
        _writer.enqueueCritical(
          HarnessStatusIpcPublisher._error('subscription_busy'),
        );
        return;
      }
      _subscribed = true;
      _statusSubscription = publisher.snapshotStream().listen(
        _statusChanged,
        onError: (Object _, StackTrace _) {
          // Provider failures are isolated; heartbeat/snapshot reads can retry.
        },
      );
      publisher._notify(
        HarnessStatusIpcEventType.subscriptionStarted,
        peerId: _peerId,
        streamSequence: _latestSequence,
      );
    }
    await _sendCurrentSnapshot(full: true);
    _scheduleHeartbeat();
  }

  void _statusChanged(Map<String, Object?> snapshot) {
    if (_closed || !_subscribed) return;
    _remember(snapshot);
    _writer.enqueueLatest(_snapshotEnvelope(snapshot, full: false));
    _scheduleHeartbeat();
  }

  Future<void> _sendCurrentSnapshot({required bool full}) async {
    try {
      final Map<String, Object?> snapshot = await publisher.snapshotProvider();
      if (_closed) return;
      _remember(snapshot);
      _writer.enqueueLatest(_snapshotEnvelope(snapshot, full: full));
    } on Object {
      _writer.enqueueCritical(
        HarnessStatusIpcPublisher._error('internal_error'),
      );
    }
  }

  Map<String, Object?> _snapshotEnvelope(
    Map<String, Object?> snapshot, {
    required bool full,
  }) {
    final Map<String, Object?> envelope = <String, Object?>{
      'type': 'snapshot',
      'protocolVersion': harnessStatusProtocolVersion,
      'full': full,
      'streamSequence': _sequenceOf(snapshot),
      'payload': snapshot,
    };
    return _fitSnapshotEnvelope(envelope, snapshot);
  }

  Map<String, Object?> _fitSnapshotEnvelope(
    Map<String, Object?> envelope,
    Map<String, Object?> snapshot,
  ) {
    if (_fits(envelope)) return envelope;
    final Object? tasksValue = snapshot['tasks'];
    if (tasksValue is List) {
      final List<Object?> tasks = List<Object?>.from(tasksValue);
      while (tasks.isNotEmpty) {
        // Registry snapshots are newest-first. Preserve the freshest work and
        // trim the oldest entries when a peer negotiated a smaller frame.
        tasks.removeLast();
        final Map<String, Object?> reduced = Map<String, Object?>.from(snapshot)
          ..['tasks'] = tasks;
        reduced['truncated'] = true;
        final Map<String, Object?> candidate = Map<String, Object?>.from(
          envelope,
        )..['payload'] = reduced;
        if (_fits(candidate)) return candidate;
      }
    }
    final Map<String, Object?> minimal = <String, Object?>{
      if (snapshot['schema'] != null) 'schema': snapshot['schema'],
      'streamSequence': _sequenceOf(snapshot),
      if (snapshot['generatedAt'] != null)
        'generatedAt': snapshot['generatedAt'],
      if (snapshot['aggregate'] != null) 'aggregate': snapshot['aggregate'],
      'tasks': const <Object?>[],
      'truncated': true,
    };
    final Map<String, Object?> candidate = Map<String, Object?>.from(envelope)
      ..['payload'] = minimal;
    if (_fits(candidate)) return candidate;
    return HarnessStatusIpcPublisher._error('frame_too_large');
  }

  bool _fits(Map<String, Object?> message) {
    try {
      HarnessStatusFrameCodec.encode(
        message,
        maxFrameBytes: _negotiatedMaxFrame,
      );
      return true;
    } on Object {
      return false;
    }
  }

  void _remember(Map<String, Object?> snapshot) {
    _latestSequence = _sequenceOf(snapshot);
    final Object? aggregate = snapshot['aggregate'];
    if (aggregate is Map && aggregate['busyCount'] is int) {
      _busy = (aggregate['busyCount']! as int) > 0;
      return;
    }
    final Object? tasks = snapshot['tasks'];
    _busy = tasks is List && tasks.any(_taskIsBusy);
  }

  bool _taskIsBusy(Object? task) {
    if (task is! Map) return false;
    return const <String>{
      'starting',
      'queued',
      'planning',
      'reasoning',
      'waitingApproval',
      'invokingTool',
      'toolRunning',
      'synthesizing',
      'runningTool',
    }.contains(task['phase']);
  }

  int _sequenceOf(Map<String, Object?> snapshot) {
    final Object? value = snapshot['streamSequence'];
    return value is int && value >= 0 ? value : 0;
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!_subscribed || _closed) return;
    final Duration interval = _busy
        ? publisher.busyHeartbeat
        : publisher.idleHeartbeat;
    _heartbeatTimer = Timer(interval, () {
      if (!_subscribed || _closed) return;
      _writer.enqueueHeartbeat(<String, Object?>{
        'type': 'heartbeat',
        'protocolVersion': harnessStatusProtocolVersion,
        'peerId': _peerId,
        'streamSequence': _latestSequence,
        'suggestedIntervalMs': interval.inMilliseconds,
        'busy': _busy,
      });
      publisher._notify(
        HarnessStatusIpcEventType.heartbeatSent,
        peerId: _peerId,
        streamSequence: _latestSequence,
      );
      _scheduleHeartbeat();
    });
  }

  Future<void> _unsubscribe() async {
    if (!_subscribed) {
      _writer.enqueueCritical(
        HarnessStatusIpcPublisher._error('not_subscribed'),
      );
      return;
    }
    _subscribed = false;
    publisher._releaseSubscription();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    publisher._notify(
      HarnessStatusIpcEventType.unsubscribed,
      peerId: _peerId,
      streamSequence: _latestSequence,
    );
  }

  Future<void> _fatal(String code) async {
    if (_closed) return;
    _writer.enqueueCritical(HarnessStatusIpcPublisher._error(code));
    await _writer.closeWhenDrained();
    await close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _inputSubscription?.cancel();
    if (_subscribed) {
      _subscribed = false;
      publisher._releaseSubscription();
    }
    await _statusSubscription?.cancel();
    _writer.destroy();
    if (_handshaken) {
      publisher._notify(
        HarnessStatusIpcEventType.disconnected,
        peerId: _peerId,
        streamSequence: _latestSequence,
      );
    }
    onClosed();
  }
}

class _LatestWinsFrameWriter {
  _LatestWinsFrameWriter(this.connection);

  final HarnessStatusIpcConnection connection;
  int maxFrameBytes = harnessStatusMaxFrameBytes;
  final List<Map<String, Object?>> _critical = <Map<String, Object?>>[];
  Map<String, Object?>? _latest;
  bool _writing = false;
  bool _destroyed = false;
  Completer<void>? _drained;

  void enqueueCritical(Map<String, Object?> message) {
    if (_destroyed) return;
    if (_critical.length >= 8) {
      destroy();
      return;
    }
    _critical.add(message);
    _drain();
  }

  void enqueueLatest(Map<String, Object?> message) {
    if (_destroyed) return;
    _latest = message;
    _drain();
  }

  void enqueueHeartbeat(Map<String, Object?> message) {
    if (_destroyed || _latest != null) return;
    _latest = message;
    _drain();
  }

  void _drain() {
    if (_writing || _destroyed) return;
    _writing = true;
    unawaited(_writeLoop());
  }

  Future<void> _writeLoop() async {
    try {
      while (!_destroyed) {
        final Map<String, Object?>? message = _critical.isNotEmpty
            ? _critical.removeAt(0)
            : _takeLatest();
        if (message == null) break;
        final List<int> encoded = HarnessStatusFrameCodec.encode(
          message,
          maxFrameBytes: maxFrameBytes,
        );
        connection.add(encoded);
        await connection.flush();
      }
    } on Object {
      destroy();
    } finally {
      _writing = false;
      if (!_destroyed && (_critical.isNotEmpty || _latest != null)) {
        _drain();
      } else if (_critical.isEmpty && _latest == null) {
        _drained?.complete();
        _drained = null;
      }
    }
  }

  Map<String, Object?>? _takeLatest() {
    final Map<String, Object?>? latest = _latest;
    _latest = null;
    return latest;
  }

  Future<void> closeWhenDrained() async {
    if (_destroyed) return;
    if (_writing || _critical.isNotEmpty || _latest != null) {
      _drained ??= Completer<void>();
      await _drained!.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
    if (!_destroyed) {
      try {
        await connection.close();
      } on Object {
        connection.destroy();
      }
    }
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _critical.clear();
    _latest = null;
    connection.destroy();
    _drained?.complete();
    _drained = null;
  }
}
