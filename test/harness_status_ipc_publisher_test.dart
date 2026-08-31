import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_status_ipc_protocol.dart';
import 'package:vibekits/features/dev_tools/domain/harness_status_ipc_publisher.dart';
import 'package:vibekits/features/dev_tools/domain/harness_status_ipc_transport.dart';

void main() {
  test('production Unix endpoint fits the platform sockaddr limit', () {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final String endpoint =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        '$harnessStatusRuntimeDirectoryName${Platform.pathSeparator}'
        '$harnessStatusSocketName';
    final int limit = Platform.isMacOS ? 104 : 108;

    expect(utf8.encode(endpoint).length, lessThan(limit), reason: endpoint);
  });

  group('real Unix-domain socket publisher', () {
    late Directory root;
    late StreamController<Map<String, Object?>> changes;
    late Map<String, Object?> current;
    late HarnessStatusIpcPublisher publisher;
    late List<HarnessStatusIpcEvent> events;

    setUp(() async {
      root = Directory('/private/tmp/vibekits-ipc-test-$pid');
      if (await root.exists()) await root.delete(recursive: true);
      await root.create();
      changes = StreamController<Map<String, Object?>>.broadcast(sync: true);
      events = <HarnessStatusIpcEvent>[];
      current = _snapshot(sequence: 1, busy: false);
      publisher = HarnessStatusIpcPublisher(
        snapshotProvider: () => current,
        snapshotStream: () => changes.stream,
        publisherVersion: 'test-version',
        transport: UnixHarnessStatusIpcTransport(runtimeRoot: root),
        busyHeartbeat: const Duration(milliseconds: 20),
        idleHeartbeat: const Duration(milliseconds: 70),
        instanceId: 'publisher-test-instance',
        observer: events.add,
      );
    });

    tearDown(() async {
      await publisher.stop();
      await changes.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('uses fixed protected path and validates the real peer UID', () async {
      final HarnessStatusIpcStartResult result = await publisher.start();
      final String expected =
          '${root.path}/$harnessStatusRuntimeDirectoryName/'
          '$harnessStatusSocketName';

      expect(result.available, isTrue, reason: result.reason);
      expect(result.endpoint, expected);
      expect((await FileStat.stat(expected)).mode & 0x1ff, 0x180);
      expect(
        (await FileStat.stat('${root.path}/$harnessStatusRuntimeDirectoryName'))
                .mode &
            0x1ff,
        0x1c0,
      );

      final _UnixTestClient client = await _UnixTestClient.connect(expected);
      addTearDown(client.close);
      final Future<Map<String, Object?>> ack = client.next('helloAck');
      client.send(_hello(nonce: 'nonce-path', maxFrameBytes: 65536));
      final Map<String, Object?> handshake = await ack;
      expect(handshake['nonce'], 'nonce-path');
      expect(handshake['maxFrameBytes'], harnessStatusMaxFrameBytes);
    });

    test(
      'negotiates hello and serves snapshot, resync and unsubscribe',
      () async {
        await publisher.start();
        final _UnixTestClient client = await _UnixTestClient.connect(
          publisher.endpoint,
        );
        addTearDown(client.close);

        final Future<Map<String, Object?>> ackFuture = client.next('helloAck');
        client.send(_hello(nonce: 'nonce-echo', maxFrameBytes: 4096));
        final Map<String, Object?> ack = await ackFuture;
        expect(ack['protocol'], harnessStatusProtocol);
        expect(ack['selectedVersion'], 1);
        expect(ack['nonce'], 'nonce-echo');
        expect(ack['maxFrameBytes'], 4096);
        expect(ack['instanceId'], 'publisher-test-instance');
        expect(events.last.type, HarnessStatusIpcEventType.handshakeSucceeded);

        final Future<Map<String, Object?>> snapshotFuture = client.next(
          'snapshot',
        );
        client.send(<String, Object?>{'type': 'getSnapshot'});
        expect((await snapshotFuture)['streamSequence'], 1);

        final Future<Map<String, Object?>> subscribed = client.next('snapshot');
        client.send(<String, Object?>{
          'type': 'subscribe',
          'afterStreamSequence': 1,
        });
        expect((await subscribed)['full'], isTrue);
        expect(publisher.activeSubscriptionCount, 1);
        expect(
          events.map((HarnessStatusIpcEvent event) => event.type),
          contains(HarnessStatusIpcEventType.subscriptionStarted),
        );

        current = _snapshot(sequence: 2, busy: true);
        final Future<Map<String, Object?>> changed = client.next('snapshot');
        changes.add(current);
        expect((await changed)['streamSequence'], 2);

        final Future<Map<String, Object?>> heartbeat = client.next('heartbeat');
        final Map<String, Object?> busyHeartbeat = await heartbeat;
        expect(busyHeartbeat['busy'], isTrue);
        expect(busyHeartbeat['suggestedIntervalMs'], 20);
        expect(
          events.map((HarnessStatusIpcEvent event) => event.type),
          contains(HarnessStatusIpcEventType.heartbeatSent),
        );

        final Future<Map<String, Object?>> resynced = client.next('snapshot');
        client.send(<String, Object?>{
          'type': 'resync',
          'afterStreamSequence': 1,
        });
        expect((await resynced)['full'], isTrue);

        client.send(<String, Object?>{'type': 'unsubscribe'});
        await _eventually(() => publisher.activeSubscriptionCount == 0);
        expect(
          events.map((HarnessStatusIpcEvent event) => event.type),
          contains(HarnessStatusIpcEventType.unsubscribed),
        );
        final Future<Map<String, Object?>> notSubscribed = client.next('error');
        client.send(<String, Object?>{
          'type': 'resync',
          'afterStreamSequence': 2,
        });
        expect((await notSubscribed)['code'], 'not_subscribed');
        await client.close();
        await _eventually(
          () => events.any(
            (HarnessStatusIpcEvent event) =>
                event.type == HarnessStatusIpcEventType.disconnected,
          ),
        );
      },
    );

    test(
      'invalid version and oversized frame close only that client',
      () async {
        await publisher.start();
        final _UnixTestClient rejected = await _UnixTestClient.connect(
          publisher.endpoint,
        );
        addTearDown(rejected.close);
        final Future<Map<String, Object?>> unsupported = rejected.next('error');
        rejected.send(_hello(nonce: 'bad-version', versions: <int>[99]));
        expect((await unsupported)['code'], 'unsupported_version');

        final _UnixTestClient oversized = await _UnixTestClient.connect(
          publisher.endpoint,
        );
        addTearDown(oversized.close);
        final Future<Map<String, Object?>> tooLarge = oversized.next('error');
        oversized.sendRaw(<int>[0, 0, 128, 1]);
        expect((await tooLarge)['code'], 'frame_too_large');

        final _UnixTestClient healthy = await _UnixTestClient.connect(
          publisher.endpoint,
        );
        addTearDown(healthy.close);
        final Future<Map<String, Object?>> ack = healthy.next('helloAck');
        healthy.send(_hello(nonce: 'healthy-client'));
        expect((await ack)['nonce'], 'healthy-client');
      },
    );

    test(
      'reports a busy subscription and allows retry after disconnect',
      () async {
        await publisher.start();
        final _UnixTestClient first = await _UnixTestClient.connect(
          publisher.endpoint,
        );
        addTearDown(first.close);
        final Future<Map<String, Object?>> firstAck = first.next('helloAck');
        first.send(_hello(nonce: 'first-subscriber'));
        await firstAck;
        final Future<Map<String, Object?>> firstSnapshot = first.next(
          'snapshot',
        );
        first.send(<String, Object?>{
          'type': 'subscribe',
          'afterStreamSequence': 0,
        });
        await firstSnapshot;
        expect(publisher.activeSubscriptionCount, 1);

        final _UnixTestClient second = await _UnixTestClient.connect(
          publisher.endpoint,
        );
        addTearDown(second.close);
        final Future<Map<String, Object?>> secondAck = second.next('helloAck');
        second.send(_hello(nonce: 'second-subscriber'));
        await secondAck;
        final Future<Map<String, Object?>> busy = second.next('error');
        second.send(<String, Object?>{
          'type': 'subscribe',
          'afterStreamSequence': 0,
        });
        expect((await busy)['code'], 'subscription_busy');

        await first.close();
        await _eventually(() => publisher.activeSubscriptionCount == 0);
        final Future<Map<String, Object?>> retried = second.next('snapshot');
        second.send(<String, Object?>{
          'type': 'subscribe',
          'afterStreamSequence': 0,
        });
        expect((await retried)['streamSequence'], 1);
        expect(publisher.activeSubscriptionCount, 1);
      },
    );
  });

  test('wrong local identity is rejected before handshake', () async {
    final _FakeTransport transport = _FakeTransport(localIdentity: 'uid-501');
    final HarnessStatusIpcPublisher publisher = HarnessStatusIpcPublisher(
      snapshotProvider: () => _snapshot(sequence: 0, busy: false),
      snapshotStream: () => const Stream<Map<String, Object?>>.empty(),
      publisherVersion: 'test',
      transport: transport,
    );
    addTearDown(publisher.stop);
    await publisher.start();
    final _FakeConnection connection = _FakeConnection(peerIdentity: 'uid-502');
    final Future<Map<String, Object?>> errorFuture = connection.nextOutput(
      'error',
    );
    transport.accept(connection);
    final Map<String, Object?> error = await errorFuture;
    expect(error['code'], 'unauthorized_peer');
    expect(publisher.activeConnectionCount, 0);
  });

  test('latest-wins replaces a pending slow-subscriber snapshot', () async {
    final StreamController<Map<String, Object?>> changes =
        StreamController<Map<String, Object?>>.broadcast(sync: true);
    Map<String, Object?> current = _snapshot(sequence: 1, busy: false);
    final _FakeTransport transport = _FakeTransport(localIdentity: 'same');
    final HarnessStatusIpcPublisher publisher = HarnessStatusIpcPublisher(
      snapshotProvider: () => current,
      snapshotStream: () => changes.stream,
      publisherVersion: 'test',
      transport: transport,
      idleHeartbeat: const Duration(days: 1),
      busyHeartbeat: const Duration(days: 1),
    );
    addTearDown(() async {
      await publisher.stop();
      await changes.close();
    });
    await publisher.start();
    final _FakeConnection connection = _FakeConnection(peerIdentity: 'same');
    transport.accept(connection);
    final Future<Map<String, Object?>> ackFuture = connection.nextOutput(
      'helloAck',
    );
    connection.sendInput(_hello(nonce: 'latest-wins'));
    await ackFuture;
    final Future<Map<String, Object?>> initialSnapshot = connection.nextOutput(
      'snapshot',
    );
    connection.sendInput(<String, Object?>{
      'type': 'subscribe',
      'afterStreamSequence': 0,
    });
    await initialSnapshot;

    connection.blockFlush();
    current = _snapshot(sequence: 2, busy: true);
    final Future<Map<String, Object?>> firstChanged = connection.nextOutput(
      'snapshot',
    );
    changes.add(current);
    await firstChanged;
    current = _snapshot(sequence: 3, busy: true);
    changes.add(current);
    current = _snapshot(sequence: 4, busy: true);
    changes.add(current);
    final Future<Map<String, Object?>> latestFuture = connection.nextOutput(
      'snapshot',
    );
    connection.releaseFlush();

    final Map<String, Object?> latest = await latestFuture;
    expect(latest['streamSequence'], 4);
    expect(
      connection.outputs.where((Map<String, Object?> message) {
        return message['type'] == 'snapshot' && message['streamSequence'] == 3;
      }),
      isEmpty,
    );
  });

  test('unavailable transport fails closed without a TCP fallback', () async {
    final HarnessStatusIpcPublisher publisher = HarnessStatusIpcPublisher(
      snapshotProvider: () => _snapshot(sequence: 0, busy: false),
      snapshotStream: () => const Stream<Map<String, Object?>>.empty(),
      publisherVersion: 'test',
      transport: const UnavailableHarnessStatusIpcTransport(
        'named pipe unavailable',
      ),
    );
    final HarnessStatusIpcStartResult result = await publisher.start();
    expect(result.available, isFalse);
    expect(result.reason, 'named pipe unavailable');
    expect(publisher.endpoint, isEmpty);
  });
}

Map<String, Object?> _snapshot({
  required int sequence,
  required bool busy,
}) => <String, Object?>{
  'schema': 'vibekits.harness.status/v1',
  'streamSequence': sequence,
  'generatedAt': DateTime.utc(2026, 8, 30).toIso8601String(),
  'aggregate': <String, Object?>{
    'taskCount': busy ? 1 : 0,
    'busyCount': busy ? 1 : 0,
    'waitingApprovalCount': 0,
    'failedCount': 0,
  },
  'tasks': busy
      ? <Object?>[
          <String, Object?>{'taskId': 'task-$sequence', 'phase': 'toolRunning'},
        ]
      : const <Object?>[],
};

Map<String, Object?> _hello({
  required String nonce,
  List<int> versions = const <int>[1],
  int maxFrameBytes = harnessStatusMaxFrameBytes,
}) => <String, Object?>{
  'type': 'hello',
  'protocol': harnessStatusProtocol,
  'versions': versions,
  'client': 'kemi-rustdesk',
  'peerId': 'local-host-session',
  'nonce': nonce,
  'maxFrameBytes': maxFrameBytes,
};

Future<void> _eventually(bool Function() predicate) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition did not become true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _UnixTestClient {
  _UnixTestClient._(this.socket) {
    _subscription = socket.listen((List<int> bytes) {
      for (final Map<String, Object?> message in _decoder.add(bytes)) {
        _messages.add(message);
      }
    });
  }

  final Socket socket;
  final HarnessStatusFrameDecoder _decoder = HarnessStatusFrameDecoder();
  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>.broadcast();
  late final StreamSubscription<List<int>> _subscription;
  bool _closed = false;

  static Future<_UnixTestClient> connect(String path) async {
    final Socket socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return _UnixTestClient._(socket);
  }

  Future<Map<String, Object?>> next(String type) => _messages.stream
      .firstWhere((Map<String, Object?> message) => message['type'] == type)
      .timeout(const Duration(seconds: 3));

  void send(Map<String, Object?> message) =>
      socket.add(HarnessStatusFrameCodec.encode(message));

  void sendRaw(List<int> bytes) => socket.add(bytes);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    socket.destroy();
    await _subscription.cancel();
    await _messages.close();
  }
}

class _FakeTransport implements HarnessStatusIpcTransport {
  _FakeTransport({required String localIdentity})
    : listener = _FakeListener(localIdentity);

  final _FakeListener listener;

  @override
  Future<HarnessStatusIpcListener> bind() async => listener;

  void accept(HarnessStatusIpcConnection connection) =>
      listener.controller.add(connection);
}

class _FakeListener implements HarnessStatusIpcListener {
  _FakeListener(this.localIdentity);

  final StreamController<HarnessStatusIpcConnection> controller =
      StreamController<HarnessStatusIpcConnection>.broadcast(sync: true);

  @override
  final String localIdentity;

  @override
  String get endpoint => 'fake://harness-status';

  @override
  Stream<HarnessStatusIpcConnection> get connections => controller.stream;

  @override
  Future<void> close() => controller.close();
}

class _FakeConnection implements HarnessStatusIpcConnection {
  _FakeConnection({required this.peerIdentity});

  @override
  final String? peerIdentity;

  final StreamController<List<int>> _input =
      StreamController<List<int>>.broadcast(sync: true);
  final HarnessStatusFrameDecoder _outputDecoder = HarnessStatusFrameDecoder();
  final List<Map<String, Object?>> outputs = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _pendingOutputs = <Map<String, Object?>>[];
  final List<_OutputWaiter> _waiters = <_OutputWaiter>[];
  Completer<void>? _blockedFlush;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void add(List<int> data) {
    for (final Map<String, Object?> message in _outputDecoder.add(data)) {
      outputs.add(message);
      final int waiterIndex = _waiters.indexWhere(
        (_OutputWaiter waiter) => waiter.type == message['type'],
      );
      if (waiterIndex >= 0) {
        _waiters.removeAt(waiterIndex).completer.complete(message);
      } else {
        _pendingOutputs.add(message);
      }
    }
  }

  @override
  Future<void> flush() => _blockedFlush?.future ?? Future<void>.value();

  void blockFlush() => _blockedFlush = Completer<void>();

  void releaseFlush() {
    _blockedFlush?.complete();
    _blockedFlush = null;
  }

  void sendInput(Map<String, Object?> message) =>
      _input.add(HarnessStatusFrameCodec.encode(message));

  Future<Map<String, Object?>> nextOutput(String type) {
    final int pendingIndex = _pendingOutputs.indexWhere(
      (Map<String, Object?> message) => message['type'] == type,
    );
    if (pendingIndex >= 0) {
      return Future<Map<String, Object?>>.value(
        _pendingOutputs.removeAt(pendingIndex),
      );
    }
    final _OutputWaiter waiter = _OutputWaiter(type);
    _waiters.add(waiter);
    return waiter.completer.future.timeout(const Duration(seconds: 3));
  }

  @override
  Future<void> close() async {
    await _input.close();
  }

  @override
  void destroy() {
    unawaited(_input.close());
  }
}

class _OutputWaiter {
  _OutputWaiter(this.type);

  final String type;
  final Completer<Map<String, Object?>> completer =
      Completer<Map<String, Object?>>();
}
