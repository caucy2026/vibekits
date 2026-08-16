import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum RemoteSessionMode { ssh, sftp, localForward }

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

  void validate() {
    _validateHost(host, label: '主机');
    final String login = user.trim();
    if (login.isEmpty ||
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

  String get executable => mode == RemoteSessionMode.sftp ? 'sftp' : 'ssh';

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

abstract final class RemoteSessionService {
  static Future<RemoteSessionHandle> start(RemoteLaunchRequest request) async {
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

class _ProcessRemoteSession implements RemoteSessionHandle {
  _ProcessRemoteSession(this._process) {
    _stdout = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_output.add);
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
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
