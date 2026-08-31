import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

enum RemoteSessionMode { ssh, sftp, localForward, remoteDesktop }

/// A cross-workspace request to prepare an interactive SSH task.
///
/// It deliberately contains no password. Authentication remains an explicit
/// user interaction in the remote workspace, after which the same SSH client
/// can open SFTP without asking again.
class RemoteWorkspaceIntent {
  const RemoteWorkspaceIntent({
    required this.host,
    this.user = '',
    this.port = 22,
    this.openSftpAfterConnect = true,
  });

  final String host;
  final String user;
  final int port;
  final bool openSftpAfterConnect;

  void validate() => RemoteConnectionProfile(
    host: host,
    user: user,
    port: port,
  ).validate(requireUser: false);
}

class RemoteConnectionProfile {
  const RemoteConnectionProfile({
    required this.host,
    required this.user,
    this.port = 22,
    this.identityFile,
  });

  final String host;
  final String user;
  final int port;
  final String? identityFile;

  void validate({bool requireUser = true}) {
    _validateHost(host, label: '主机');
    final String login = user.trim();
    if (requireUser && login.isEmpty ||
        login.length > 128 ||
        login.codeUnits.any((int unit) => unit < 0x20) ||
        login.startsWith('-')) {
      throw const FormatException('用户名格式无效');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('SSH 端口必须在 1 到 65535 之间');
    }
    final String? key = identityFile?.trim();
    if (key != null && key.isNotEmpty) {
      if (FileSystemEntity.typeSync(key, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('私钥路径不是可访问的普通文件');
      }
    }
  }
}

class RemoteLaunchRequest {
  const RemoteLaunchRequest({
    required this.mode,
    required this.profile,
    this.localPort,
    this.targetHost,
    this.targetPort,
  });

  final RemoteSessionMode mode;
  final RemoteConnectionProfile profile;
  final int? localPort;
  final String? targetHost;
  final int? targetPort;

  String get executable => switch (mode) {
    RemoteSessionMode.sftp => 'sftp',
    RemoteSessionMode.ssh || RemoteSessionMode.localForward => 'ssh',
    RemoteSessionMode.remoteDesktop => throw UnsupportedError(
      '远程桌面必须使用系统客户端服务',
    ),
  };

  List<String> buildArguments() {
    profile.validate();
    final bool sftp = mode == RemoteSessionMode.sftp;
    final List<String> arguments = <String>[
      sftp ? '-P' : '-p',
      '${profile.port}',
      '-l',
      profile.user.trim(),
      '-o',
      'BatchMode=yes',
      '-o',
      'StrictHostKeyChecking=ask',
      '-o',
      'ConnectTimeout=10',
      '-o',
      'ServerAliveInterval=30',
      '-o',
      'ServerAliveCountMax=3',
      if (profile.identityFile?.trim().isNotEmpty == true) ...<String>[
        '-i',
        profile.identityFile!.trim(),
      ],
    ];
    switch (mode) {
      case RemoteSessionMode.ssh:
        arguments.add('-tt');
        break;
      case RemoteSessionMode.sftp:
        break;
      case RemoteSessionMode.localForward:
        final int listen = localPort ?? 0;
        final int remote = targetPort ?? 0;
        final String target = targetHost?.trim() ?? '';
        if (listen < 1 || listen > 65535) {
          throw const FormatException('本地端口必须在 1 到 65535 之间');
        }
        if (remote < 1 || remote > 65535) {
          throw const FormatException('目标端口必须在 1 到 65535 之间');
        }
        _validateHost(target, label: '转发目标');
        final String formattedTarget = target.contains(':')
            ? '[$target]'
            : target;
        arguments.addAll(<String>[
          '-N',
          '-L',
          '127.0.0.1:$listen:$formattedTarget:$remote',
          '-o',
          'ExitOnForwardFailure=yes',
        ]);
        break;
      case RemoteSessionMode.remoteDesktop:
        throw UnsupportedError('远程桌面必须使用系统客户端服务');
    }
    arguments.add(profile.host.trim());
    return arguments;
  }
}

abstract interface class RemoteSessionHandle {
  Stream<String> get output;
  Future<int> get exitCode;
  bool get running;
  void sendLine(String line);
  Future<void> stop();
}

abstract interface class RemoteInteractiveSessionHandle
    implements RemoteSessionHandle {
  void send(String data);
  void resize(int columns, int rows, int pixelWidth, int pixelHeight);
}

/// An authenticated SSH session that can open additional subsystems without
/// asking the user to authenticate again.
abstract interface class RemoteSftpSessionHandle
    implements RemoteInteractiveSessionHandle {
  Future<SftpClient> openSftp();
}

typedef RemoteHostKeyVerifier =
    Future<bool> Function(String type, String fingerprint);

class RemoteCommandResult {
  const RemoteCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract final class RemoteSessionService {
  static Future<RemoteSessionHandle> start(
    RemoteLaunchRequest request, {
    String? secret,
    RemoteHostKeyVerifier? verifyHostKey,
  }) async {
    if (request.mode == RemoteSessionMode.ssh) {
      return _DartSshRemoteSession.start(
        request,
        secret: secret,
        verifyHostKey: verifyHostKey,
      );
    }
    if (request.mode == RemoteSessionMode.localForward) {
      return _DartLocalForwardSession.start(
        request,
        secret: secret,
        verifyHostKey: verifyHostKey,
      );
    }
    return _startSystemClient(request);
  }

  static Future<RemoteSessionHandle> _startSystemClient(
    RemoteLaunchRequest request,
  ) async {
    final Process process;
    try {
      process = await Process.start(
        request.executable,
        request.buildArguments(),
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (error) {
      throw StateError(
        '未找到系统 ${request.executable}，请安装 OpenSSH Client：${error.message}',
      );
    }
    return _ProcessRemoteSession(process);
  }
}

class _DartLocalForwardSession implements RemoteSessionHandle {
  _DartLocalForwardSession._(
    this._client,
    this._server,
    this._remoteHost,
    this._remotePort,
  ) {
    _output.add(
      '本地转发已启动：127.0.0.1:${_server.port} → '
      '$_remoteHost:$_remotePort\n',
    );
    _connections = _server.listen(_accept, onError: _onServerError);
    _client.done.then((_) => _finish(-1));
  }

  static Future<_DartLocalForwardSession> start(
    RemoteLaunchRequest request, {
    String? secret,
    RemoteHostKeyVerifier? verifyHostKey,
  }) async {
    request.buildArguments();
    final SSHClient client = await RemoteSshConnector.connect(
      request.profile,
      secret: secret,
      verifyHostKey: verifyHostKey,
    );
    try {
      final ServerSocket server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        request.localPort!,
        shared: false,
      );
      return _DartLocalForwardSession._(
        client,
        server,
        request.targetHost!.trim(),
        request.targetPort!,
      );
    } on Object {
      client.close();
      rethrow;
    }
  }

  final SSHClient _client;
  final ServerSocket _server;
  final String _remoteHost;
  final int _remotePort;
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  final Set<Socket> _sockets = <Socket>{};
  final Set<SSHForwardChannel> _channels = <SSHForwardChannel>{};
  late final StreamSubscription<Socket> _connections;
  bool _running = true;

  Future<void> _accept(Socket socket) async {
    if (!_running) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    try {
      final SSHForwardChannel channel = await _client.forwardLocal(
        _remoteHost,
        _remotePort,
        localHost: socket.remoteAddress.address,
        localPort: socket.remotePort,
      );
      if (!_running) {
        channel.destroy();
        socket.destroy();
        return;
      }
      _channels.add(channel);
      unawaited(channel.stream.cast<List<int>>().pipe(socket));
      unawaited(socket.cast<List<int>>().pipe(channel.sink));
      unawaited(
        channel.done.whenComplete(() {
          _channels.remove(channel);
          _sockets.remove(socket);
          socket.destroy();
        }),
      );
    } on Object catch (error) {
      _sockets.remove(socket);
      socket.destroy();
      if (_running) _output.add('转发连接失败：$error\n');
    }
  }

  void _onServerError(Object error) {
    if (_running) _output.add('本地监听失败：$error\n');
  }

  Future<void> _finish(int code) async {
    if (!_running) return;
    _running = false;
    await _server.close();
    await _connections.cancel();
    for (final Socket socket in _sockets.toList()) {
      socket.destroy();
    }
    for (final SSHForwardChannel channel in _channels.toList()) {
      channel.destroy();
    }
    _client.close();
    if (!_exit.isCompleted) _exit.complete(code);
    await _output.close();
  }

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool get running => _running;

  @override
  void sendLine(String line) {}

  @override
  Future<void> stop() => _finish(0);
}

abstract final class RemoteSshConnector {
  static Future<SSHClient> connect(
    RemoteConnectionProfile profile, {
    String? secret,
    RemoteHostKeyVerifier? verifyHostKey,
  }) async {
    profile.validate();
    final String? identityPath = profile.identityFile?.trim();
    List<SSHKeyPair>? identities;
    if (identityPath?.isNotEmpty == true) {
      final String pem = await File(identityPath!).readAsString();
      identities = SSHKeyPair.fromPem(
        pem,
        secret?.isEmpty == true ? null : secret,
      );
    }
    final SSHSocket socket = await SSHSocket.connect(
      profile.host.trim(),
      profile.port,
      timeout: const Duration(seconds: 10),
    );
    final SSHClient client = SSHClient(
      socket,
      username: profile.user.trim(),
      identities: identities,
      onPasswordRequest: identityPath?.isNotEmpty == true
          ? null
          : () => secret?.isEmpty == true ? null : secret,
      onVerifyHostKey: (String type, Uint8List fingerprint) async {
        final RemoteHostKeyVerifier? verifier = verifyHostKey;
        if (verifier == null) return false;
        return verifier(type, utf8.decode(fingerprint));
      },
      handshakeTimeout: const Duration(seconds: 12),
      authTimeout: const Duration(seconds: 15),
      keepAliveInterval: const Duration(seconds: 20),
    );
    try {
      await client.authenticated;
      return client;
    } on Object {
      client.close();
      rethrow;
    }
  }

  static Future<RemoteCommandResult> runCommand(
    RemoteConnectionProfile profile,
    String command, {
    String? secret,
    required RemoteHostKeyVerifier verifyHostKey,
  }) async {
    final String source = command.trim();
    if (source.isEmpty ||
        source.length > 8192 ||
        source.codeUnits.any((int unit) => unit == 0)) {
      throw const FormatException('远程命令为空、过长或包含非法字符');
    }
    final SSHClient client = await connect(
      profile,
      secret: secret,
      verifyHostKey: verifyHostKey,
    );
    try {
      final SSHSession session = await client.execute(source);
      final Future<String> stdout = session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .join();
      final Future<String> stderr = session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .join();
      await session.done.timeout(const Duration(seconds: 30));
      return RemoteCommandResult(
        exitCode: session.exitCode ?? 0,
        stdout: await stdout,
        stderr: await stderr,
      );
    } on TimeoutException {
      client.close();
      throw StateError('远程命令 30 秒未完成，连接已关闭');
    } finally {
      client.close();
    }
  }
}

class _DartSshRemoteSession implements RemoteSftpSessionHandle {
  _DartSshRemoteSession._(this._client, this._session) {
    _stdout = _session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(_output.add, onError: _output.addError);
    _stderr = _session.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(_output.add, onError: _output.addError);
    _exit = _session.done.then((_) async {
      _running = false;
      await _stdout.cancel();
      await _stderr.cancel();
      await _output.close();
      _client.close();
      return _session.exitCode ?? 0;
    });
  }

  static Future<_DartSshRemoteSession> start(
    RemoteLaunchRequest request, {
    String? secret,
    RemoteHostKeyVerifier? verifyHostKey,
  }) async {
    final SSHClient client = await RemoteSshConnector.connect(
      request.profile,
      secret: secret,
      verifyHostKey: verifyHostKey,
    );
    try {
      await client.authenticated;
      final SSHSession session = await client.shell(
        pty: const SSHPtyConfig(width: 100, height: 30),
      );
      return _DartSshRemoteSession._(client, session);
    } on Object {
      client.close();
      rethrow;
    }
  }

  final SSHClient _client;
  final SSHSession _session;
  final StreamController<String> _output = StreamController<String>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<int> _exit;
  bool _running = true;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit;

  @override
  bool get running => _running;

  @override
  void send(String data) {
    if (!_running || data.isEmpty) return;
    _session.write(Uint8List.fromList(utf8.encode(data)));
  }

  @override
  void sendLine(String line) => send('$line\r');

  @override
  void resize(int columns, int rows, int pixelWidth, int pixelHeight) {
    if (!_running || columns < 1 || rows < 1) return;
    _session.resizeTerminal(columns, rows, pixelWidth, pixelHeight);
  }

  @override
  Future<SftpClient> openSftp() {
    if (!_running) throw StateError('SSH 会话已断开');
    return _client.sftp();
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _session.close();
    _client.close();
    await _exit.timeout(const Duration(seconds: 3), onTimeout: () => 0);
  }
}

class _ProcessRemoteSession implements RemoteSessionHandle {
  _ProcessRemoteSession(this._process) {
    _stdout = _process.stdout
        .transform(const Utf8Decoder())
        .listen(_output.add);
    _stderr = _process.stderr
        .transform(const Utf8Decoder())
        .listen(_output.add);
    _exit = _process.exitCode.then((int code) async {
      _running = false;
      await _stdout.cancel();
      await _stderr.cancel();
      await _output.close();
      return code;
    });
  }

  final Process _process;
  final StreamController<String> _output = StreamController<String>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<int> _exit;
  bool _running = true;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit;

  @override
  bool get running => _running;

  @override
  void sendLine(String line) {
    if (!_running) return;
    _process.stdin.writeln(line);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _process.kill();
    await _exit.timeout(const Duration(seconds: 3), onTimeout: () => -1);
  }
}

void _validateHost(String value, {required String label}) {
  final String host = value.trim();
  if (host.isEmpty ||
      host.length > 253 ||
      host.startsWith('-') ||
      host.codeUnits.any((int unit) => unit <= 0x20 || unit == 0x7f) ||
      !RegExp(r'^[A-Za-z0-9._:%-]+$').hasMatch(host)) {
    throw FormatException('$label格式无效');
  }
  if (host.contains('/') || host.contains('\\')) {
    throw FormatException('$label不能包含路径分隔符');
  }
}
