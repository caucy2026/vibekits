import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'remote_session.dart';

enum PortForwardKind { local, remote, dynamic }

class PortForwardSpec {
  const PortForwardSpec({
    required this.kind,
    required this.listenPort,
    this.targetHost,
    this.targetPort,
  });

  final PortForwardKind kind;
  final int listenPort;
  final String? targetHost;
  final int? targetPort;

  void validate() {
    if (listenPort < 1 || listenPort > 65535) {
      throw FormatException(
        kind == PortForwardKind.remote
            ? '远端监听端口必须在 1 到 65535 之间'
            : '本地监听端口必须在 1 到 65535 之间',
      );
    }
    if (kind == PortForwardKind.dynamic) return;
    final int target = targetPort ?? 0;
    if (target < 1 || target > 65535) {
      throw const FormatException('目标端口必须在 1 到 65535 之间');
    }
    _validateForwardHost(targetHost ?? '');
  }

  String get description => switch (kind) {
    PortForwardKind.local =>
      '127.0.0.1:$listenPort → ${targetHost!.trim()}:$targetPort',
    PortForwardKind.remote =>
      '远端 localhost:$listenPort → ${targetHost!.trim()}:$targetPort',
    PortForwardKind.dynamic => 'SOCKS5 127.0.0.1:$listenPort',
  };
}

abstract interface class PortForwardHandle {
  PortForwardSpec get spec;
  bool get running;
  Future<void> stop();
}

abstract interface class PortForwardConnection {
  bool get connected;
  Future<void> get done;
  Future<PortForwardHandle> start(PortForwardSpec spec);
  Future<void> close();
}

abstract final class PortForwardService {
  static Future<PortForwardConnection> connect(
    RemoteConnectionProfile profile, {
    String? secret,
    required RemoteHostKeyVerifier verifyHostKey,
  }) => _IsolatePortForwardConnection.spawn(
    profile,
    secret: secret,
    verifyHostKey: verifyHostKey,
  );

  static Future<PortForwardConnection> _connectDirect(
    RemoteConnectionProfile profile, {
    String? secret,
    required RemoteHostKeyVerifier verifyHostKey,
  }) async {
    final SSHClient ssh = await RemoteSshConnector.connect(
      profile,
      secret: secret,
      verifyHostKey: verifyHostKey,
    );
    return _DartSshPortForwardConnection(ssh);
  }
}

class _IsolatePortForwardConnection implements PortForwardConnection {
  _IsolatePortForwardConnection._(this._receiver, this._verifyHostKey) {
    _subscription = _receiver.listen(_handleMessage);
  }

  static Future<_IsolatePortForwardConnection> spawn(
    RemoteConnectionProfile profile, {
    String? secret,
    required RemoteHostKeyVerifier verifyHostKey,
  }) async {
    final ReceivePort receiver = ReceivePort();
    final _IsolatePortForwardConnection connection =
        _IsolatePortForwardConnection._(receiver, verifyHostKey);
    try {
      connection._isolate = await Isolate.spawn<List<Object?>>(
        _portForwardIsolateMain,
        <Object?>[
          receiver.sendPort,
          profile.host,
          profile.user,
          profile.port,
          profile.identityFile,
          secret,
        ],
        onExit: receiver.sendPort,
        onError: receiver.sendPort,
        errorsAreFatal: true,
        debugName: 'vibekits-port-forward',
      );
      await connection._ready.future.timeout(const Duration(seconds: 30));
      return connection;
    } on Object {
      await connection.close();
      rethrow;
    }
  }

  final ReceivePort _receiver;
  final RemoteHostKeyVerifier _verifyHostKey;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _done = Completer<void>();
  final Map<int, Completer<void>> _requests = <int, Completer<void>>{};
  late final StreamSubscription<dynamic> _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  int _nextId = 1;
  bool _closed = false;

  @override
  bool get connected => !_closed && _ready.isCompleted && !_done.isCompleted;

  @override
  Future<void> get done => _done.future;

  void _handleMessage(dynamic raw) {
    if (raw == null) {
      _finish();
      return;
    }
    if (raw is! List<Object?> || raw.isEmpty) return;
    final String type = raw.first! as String;
    switch (type) {
      case 'port':
        _commands = raw[1]! as SendPort;
        break;
      case 'verify':
        unawaited(_answerVerification(raw));
        break;
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
        break;
      case 'result':
        final int id = raw[1]! as int;
        final Completer<void>? request = _requests.remove(id);
        if (request == null) return;
        if (raw[2] == true) {
          request.complete();
        } else {
          request.completeError(StateError(raw[3]! as String));
        }
        break;
      case 'connectError':
        final StateError error = StateError(raw[1]! as String);
        if (!_ready.isCompleted) _ready.completeError(error);
        _finish(error);
        break;
    }
  }

  Future<void> _answerVerification(List<Object?> raw) async {
    final int id = raw[1]! as int;
    bool accepted = false;
    try {
      accepted = await _verifyHostKey(raw[2]! as String, raw[3]! as String);
    } on Object {
      accepted = false;
    }
    _commands?.send(<Object?>['verifyResult', id, accepted]);
  }

  Future<void> _request(List<Object?> command) {
    if (!connected) return Future<void>.error(StateError('SSH 转发连接已断开'));
    final int id = _nextId++;
    final Completer<void> result = Completer<void>();
    _requests[id] = result;
    _commands!.send(<Object?>[command.first, id, ...command.skip(1)]);
    return result.future;
  }

  @override
  Future<PortForwardHandle> start(PortForwardSpec spec) async {
    spec.validate();
    final int id = _nextId++;
    final Completer<void> result = Completer<void>();
    _requests[id] = result;
    _commands!.send(<Object?>[
      'start',
      id,
      spec.kind.name,
      spec.listenPort,
      spec.targetHost,
      spec.targetPort,
    ]);
    await result.future;
    return _IsolatePortForwardHandle(this, id, spec);
  }

  Future<void> _stop(int id) => _request(<Object?>['stop', id]);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final SendPort? commands = _commands;
    if (commands != null && !_done.isCompleted) {
      final int id = _nextId++;
      final Completer<void> result = Completer<void>();
      _requests[id] = result;
      commands.send(<Object?>['close', id]);
      await result.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    _isolate?.kill(priority: Isolate.immediate);
    _finish();
  }

  void _finish([Object? error]) {
    if (!_ready.isCompleted) {
      if (error != null) {
        _ready.completeError(error);
      } else {
        _ready.completeError(StateError('SSH 转发后台线程提前退出'));
      }
    }
    for (final Completer<void> request in _requests.values) {
      if (!request.isCompleted) {
        request.completeError(error ?? StateError('SSH 转发后台线程已退出'));
      }
    }
    _requests.clear();
    if (!_done.isCompleted) _done.complete();
    unawaited(_subscription.cancel());
    _receiver.close();
  }
}

class _IsolatePortForwardHandle implements PortForwardHandle {
  _IsolatePortForwardHandle(this._connection, this._id, this.spec);

  final _IsolatePortForwardConnection _connection;
  final int _id;

  @override
  final PortForwardSpec spec;

  bool _running = true;

  @override
  bool get running => _running && _connection.connected;

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    if (_connection.connected) await _connection._stop(_id);
  }
}

Future<void> _portForwardIsolateMain(List<Object?> arguments) async {
  final SendPort main = arguments[0]! as SendPort;
  final RemoteConnectionProfile profile = RemoteConnectionProfile(
    host: arguments[1]! as String,
    user: arguments[2]! as String,
    port: arguments[3]! as int,
    identityFile: arguments[4] as String?,
  );
  final String? secret = arguments[5] as String?;
  final ReceivePort commands = ReceivePort();
  main.send(<Object?>['port', commands.sendPort]);
  final Map<int, Completer<bool>> verifications = <int, Completer<bool>>{};
  final Map<int, PortForwardHandle> handles = <int, PortForwardHandle>{};
  int nextVerification = 1;
  PortForwardConnection? connection;
  bool closing = false;

  late final StreamSubscription<dynamic> subscription;
  subscription = commands.listen((dynamic raw) {
    if (raw is! List<Object?> || raw.isEmpty) return;
    final String type = raw.first! as String;
    if (type == 'verifyResult') {
      verifications.remove(raw[1]! as int)?.complete(raw[2] == true);
      return;
    }
    unawaited(() async {
      final int requestId = raw[1]! as int;
      try {
        switch (type) {
          case 'start':
            final PortForwardKind kind = PortForwardKind.values.firstWhere(
              (PortForwardKind value) => value.name == raw[2],
            );
            final PortForwardSpec spec = PortForwardSpec(
              kind: kind,
              listenPort: raw[3]! as int,
              targetHost: raw[4] as String?,
              targetPort: raw[5] as int?,
            );
            final PortForwardHandle handle = await connection!.start(spec);
            handles[requestId] = handle;
            main.send(<Object?>['result', requestId, true]);
            break;
          case 'stop':
            final int handleId = raw[2]! as int;
            await handles.remove(handleId)?.stop();
            main.send(<Object?>['result', requestId, true]);
            break;
          case 'close':
            if (closing) return;
            closing = true;
            await connection?.close();
            handles.clear();
            main.send(<Object?>['result', requestId, true]);
            await subscription.cancel();
            commands.close();
            break;
        }
      } on Object catch (error) {
        main.send(<Object?>[
          'result',
          requestId,
          false,
          _forwardErrorText(error),
        ]);
      }
    }());
  });

  try {
    connection = await PortForwardService._connectDirect(
      profile,
      secret: secret,
      verifyHostKey: (String type, String fingerprint) async {
        final int id = nextVerification++;
        final Completer<bool> result = Completer<bool>();
        verifications[id] = result;
        main.send(<Object?>['verify', id, type, fingerprint]);
        return result.future.timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
      },
    );
    main.send(<Object?>['ready']);
    await connection.done;
    if (!closing) {
      await subscription.cancel();
      commands.close();
    }
  } on Object catch (error) {
    main.send(<Object?>['connectError', _forwardErrorText(error)]);
    await subscription.cancel();
    commands.close();
  }
}

String _forwardErrorText(Object error) => error is FormatException
    ? error.message
    : error.toString().replaceFirst('Bad state: ', '');

class _DartSshPortForwardConnection implements PortForwardConnection {
  _DartSshPortForwardConnection(this._ssh) {
    _done = _ssh.done.whenComplete(() async {
      _closed = true;
      final List<_ManagedForwardHandle> handles = _handles.toList();
      for (final _ManagedForwardHandle handle in handles) {
        await handle.stop();
      }
    });
  }

  final SSHClient _ssh;
  final Set<_ManagedForwardHandle> _handles = <_ManagedForwardHandle>{};
  late final Future<void> _done;
  bool _closed = false;

  @override
  bool get connected => !_closed && !_ssh.isClosed;

  @override
  Future<void> get done => _done;

  @override
  Future<PortForwardHandle> start(PortForwardSpec spec) async {
    if (!connected) throw StateError('SSH 转发连接已断开');
    spec.validate();
    late final _ManagedForwardHandle handle;
    try {
      handle = switch (spec.kind) {
        PortForwardKind.local => await _LocalForwardHandle.start(
          _ssh,
          spec,
          _remove,
        ),
        PortForwardKind.remote => await _RemoteForwardHandle.start(
          _ssh,
          spec,
          _remove,
        ),
        PortForwardKind.dynamic => await _DynamicForwardHandle.start(
          _ssh,
          spec,
          _remove,
        ),
      };
    } on SocketException catch (error) {
      throw StateError(_socketError(spec, error));
    }
    _handles.add(handle);
    return handle;
  }

  void _remove(_ManagedForwardHandle handle) => _handles.remove(handle);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final List<_ManagedForwardHandle> handles = _handles.toList();
    for (final _ManagedForwardHandle handle in handles) {
      await handle.stop();
    }
    _ssh.close();
    await _done.timeout(const Duration(seconds: 3), onTimeout: () {});
  }
}

abstract class _ManagedForwardHandle implements PortForwardHandle {
  _ManagedForwardHandle(
    this.spec,
    void Function(_ManagedForwardHandle handle) onStopped,
  ) : _onStopped = onStopped;

  @override
  final PortForwardSpec spec;
  final void Function(_ManagedForwardHandle handle) _onStopped;
  bool _running = true;

  @override
  bool get running => _running;

  bool beginStop() {
    if (!_running) return false;
    _running = false;
    _onStopped(this);
    return true;
  }
}

class _LocalForwardHandle extends _ManagedForwardHandle {
  _LocalForwardHandle._(this._ssh, this._server, super.spec, super.onStopped) {
    _serverSubscription = _server.listen(_accept);
  }

  static Future<_LocalForwardHandle> start(
    SSHClient ssh,
    PortForwardSpec spec,
    void Function(_ManagedForwardHandle handle) onStopped,
  ) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      spec.listenPort,
      shared: false,
    );
    return _LocalForwardHandle._(ssh, server, spec, onStopped);
  }

  final SSHClient _ssh;
  final ServerSocket _server;
  late final StreamSubscription<Socket> _serverSubscription;
  final Set<Socket> _sockets = <Socket>{};
  final Set<SSHForwardChannel> _channels = <SSHForwardChannel>{};

  void _accept(Socket socket) {
    if (!running) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    unawaited(_open(socket));
  }

  Future<void> _open(Socket socket) async {
    SSHForwardChannel? channel;
    try {
      channel = await _ssh.forwardLocal(
        spec.targetHost!.trim(),
        spec.targetPort!,
        localHost: socket.remoteAddress.address,
        localPort: socket.remotePort,
      );
      if (!running) {
        channel.destroy();
        return;
      }
      _channels.add(channel);
      await _bridge(socket, channel);
    } on Object {
      socket.destroy();
      channel?.destroy();
    } finally {
      _sockets.remove(socket);
      if (channel != null) _channels.remove(channel);
    }
  }

  @override
  Future<void> stop() async {
    if (!beginStop()) return;
    await _serverSubscription.cancel();
    await _server.close();
    for (final Socket socket in _sockets.toList()) {
      socket.destroy();
    }
    for (final SSHForwardChannel channel in _channels.toList()) {
      channel.destroy();
    }
    _sockets.clear();
    _channels.clear();
  }
}

class _RemoteForwardHandle extends _ManagedForwardHandle {
  _RemoteForwardHandle._(this._forward, super.spec, super.onStopped) {
    _subscription = _forward.connections.listen(_accept);
  }

  static Future<_RemoteForwardHandle> start(
    SSHClient ssh,
    PortForwardSpec spec,
    void Function(_ManagedForwardHandle handle) onStopped,
  ) async {
    final SSHRemoteForward? forward = await ssh.forwardRemote(
      host: 'localhost',
      port: spec.listenPort,
    );
    if (forward == null) {
      throw StateError('远端端口 ${spec.listenPort} 被占用或服务器拒绝转发');
    }
    return _RemoteForwardHandle._(forward, spec, onStopped);
  }

  final SSHRemoteForward _forward;
  late final StreamSubscription<SSHForwardChannel> _subscription;
  final Set<Socket> _sockets = <Socket>{};
  final Set<SSHForwardChannel> _channels = <SSHForwardChannel>{};

  void _accept(SSHForwardChannel channel) {
    if (!running) {
      channel.destroy();
      return;
    }
    _channels.add(channel);
    unawaited(_open(channel));
  }

  Future<void> _open(SSHForwardChannel channel) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        spec.targetHost!.trim(),
        spec.targetPort!,
        timeout: const Duration(seconds: 10),
      );
      if (!running) {
        socket.destroy();
        channel.destroy();
        return;
      }
      _sockets.add(socket);
      await _bridge(socket, channel);
    } on Object {
      socket?.destroy();
      channel.destroy();
    } finally {
      if (socket != null) _sockets.remove(socket);
      _channels.remove(channel);
    }
  }

  @override
  Future<void> stop() async {
    if (!beginStop()) return;
    await _subscription.cancel();
    _forward.close();
    for (final Socket socket in _sockets.toList()) {
      socket.destroy();
    }
    for (final SSHForwardChannel channel in _channels.toList()) {
      channel.destroy();
    }
    _sockets.clear();
    _channels.clear();
  }
}

class _DynamicForwardHandle extends _ManagedForwardHandle {
  _DynamicForwardHandle._(this._forward, super.spec, super.onStopped);

  static Future<_DynamicForwardHandle> start(
    SSHClient ssh,
    PortForwardSpec spec,
    void Function(_ManagedForwardHandle handle) onStopped,
  ) async {
    final SSHDynamicForward forward = await ssh.forwardDynamic(
      bindHost: '127.0.0.1',
      bindPort: spec.listenPort,
    );
    return _DynamicForwardHandle._(forward, spec, onStopped);
  }

  final SSHDynamicForward _forward;

  @override
  Future<void> stop() async {
    if (!beginStop()) return;
    await _forward.close();
  }
}

Future<void> _bridge(Socket socket, SSHForwardChannel channel) async {
  late final StreamSubscription<Uint8List> localSubscription;
  late final StreamSubscription<Uint8List> remoteSubscription;
  localSubscription = socket.listen(
    channel.sink.add,
    onError: (_) => channel.destroy(),
    onDone: () => unawaited(channel.sink.close()),
    cancelOnError: true,
  );
  remoteSubscription = channel.stream.listen(
    socket.add,
    onError: (_) => socket.destroy(),
    onDone: () => unawaited(socket.close()),
    cancelOnError: true,
  );
  await Future.any<void>(<Future<void>>[socket.done, channel.done]);
  await localSubscription.cancel();
  await remoteSubscription.cancel();
  socket.destroy();
  channel.destroy();
}

String _socketError(PortForwardSpec spec, SocketException error) {
  final String detail = error.osError?.message ?? error.message;
  if (spec.kind != PortForwardKind.remote) {
    return '本地端口 ${spec.listenPort} 已占用或不可用：$detail';
  }
  return '目标连接失败：$detail';
}

void _validateForwardHost(String value) {
  final String host = value.trim();
  if (host.isEmpty ||
      host.length > 253 ||
      host.startsWith('-') ||
      host.codeUnits.any((int unit) => unit <= 0x20 || unit == 0x7f) ||
      !RegExp(r'^[A-Za-z0-9._:%-]+$').hasMatch(host) ||
      host.contains('/') ||
      host.contains('\\')) {
    throw const FormatException('目标主机格式无效');
  }
}
