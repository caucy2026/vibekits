import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HarnessEnvironmentReport {
  const HarnessEnvironmentReport({
    required this.ready,
    required this.nodeVersion,
    required this.npxVersion,
    required this.message,
  });

  final bool ready;
  final String? nodeVersion;
  final String? npxVersion;
  final String message;
}

class HarnessLaunchSpec {
  const HarnessLaunchSpec({required this.workspace, this.port = 3080});

  static const String packageSpec = '@deepseek-ai/dsh@0.1.0-rc.5';

  final String workspace;
  final int port;

  Uri get url => Uri.parse('http://127.0.0.1:$port');

  List<String> get arguments => <String>[
    '--yes',
    packageSpec,
    'web',
    '--port',
    '$port',
  ];

  void validate() {
    if (port < 1024 || port > 65535) {
      throw const FormatException('端口必须在 1024 到 65535 之间');
    }
    final Directory directory = Directory(workspace.trim());
    if (workspace.trim().isEmpty || !directory.isAbsolute) {
      throw const FormatException('请选择绝对路径的工作区');
    }
    if (!directory.existsSync()) {
      throw const FormatException('工作区不存在或无法访问');
    }
  }
}

abstract interface class HarnessSessionHandle {
  Stream<String> get output;
  Future<int> get exitCode;
  bool get running;
  Uri get url;
  Future<void> stop();
}

typedef HarnessEnvironmentChecker = Future<HarnessEnvironmentReport> Function();
typedef HarnessSessionStarter = Future<HarnessSessionHandle> Function(
  HarnessLaunchSpec spec,
);
typedef HarnessBrowserOpener = Future<void> Function(Uri url);

abstract final class DeepSeekHarnessService {
  static String get npxExecutable => Platform.isWindows ? 'npx.cmd' : 'npx';

  static Future<HarnessEnvironmentReport> checkEnvironment() async {
    try {
      final ProcessResult node = await Process.run('node', const <String>[
        '--version',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      if (node.exitCode != 0) {
        return const HarnessEnvironmentReport(
          ready: false,
          nodeVersion: null,
          npxVersion: null,
          message: '未找到可用的 Node.js',
        );
      }
      final String nodeVersion = '${node.stdout}'.trim();
      if (!_isSupportedNode(nodeVersion)) {
        return HarnessEnvironmentReport(
          ready: false,
          nodeVersion: nodeVersion,
          npxVersion: null,
          message: 'DeepSeek Harness 需要 Node.js 22.19+ 或 24+',
        );
      }
      final ProcessResult npx = await Process.run(npxExecutable, const <String>[
        '--version',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      if (npx.exitCode != 0) {
        return HarnessEnvironmentReport(
          ready: false,
          nodeVersion: nodeVersion,
          npxVersion: null,
          message: 'Node.js 已安装，但 npx 不可用',
        );
      }
      return HarnessEnvironmentReport(
        ready: true,
        nodeVersion: nodeVersion,
        npxVersion: '${npx.stdout}'.trim(),
        message: '运行环境已就绪',
      );
    } on TimeoutException {
      return const HarnessEnvironmentReport(
        ready: false,
        nodeVersion: null,
        npxVersion: null,
        message: '环境检查超时，请检查 Node.js 安装',
      );
    } on ProcessException {
      return const HarnessEnvironmentReport(
        ready: false,
        nodeVersion: null,
        npxVersion: null,
        message: '未找到 Node.js，请先安装官方 LTS 版本',
      );
    }
  }

  static Future<HarnessSessionHandle> start(HarnessLaunchSpec spec) async {
    spec.validate();
    try {
      final Process process = await Process.start(
        npxExecutable,
        spec.arguments,
        workingDirectory: spec.workspace.trim(),
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      return _ProcessHarnessSession(process, spec.url);
    } on ProcessException catch (error) {
      throw StateError('无法启动 DeepSeek Harness：${error.message}');
    }
  }

  static Future<void> openBrowser(Uri url) async {
    if (url.scheme != 'http' ||
        (url.host != '127.0.0.1' && url.host != 'localhost')) {
      throw const FormatException('只允许打开本机 Harness 地址');
    }
    final String executable;
    final List<String> arguments;
    if (Platform.isWindows) {
      executable = 'rundll32.exe';
      arguments = <String>['url.dll,FileProtocolHandler', '$url'];
    } else if (Platform.isMacOS) {
      executable = 'open';
      arguments = <String>['$url'];
    } else {
      executable = 'xdg-open';
      arguments = <String>['$url'];
    }
    await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }

  static bool _isSupportedNode(String value) {
    final Match? match = RegExp(r'v?(\d+)\.(\d+)').firstMatch(value.trim());
    if (match == null) return false;
    final int major = int.parse(match.group(1)!);
    final int minor = int.parse(match.group(2)!);
    return (major == 22 && minor >= 19) || major >= 24;
  }
}

class _ProcessHarnessSession implements HarnessSessionHandle {
  _ProcessHarnessSession(this._process, this.url) {
    _stdout = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_controller.add);
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_controller.add);
    _exitCode = _process.exitCode.then((int code) async {
      _running = false;
      await _stdout.cancel();
      await _stderr.cancel();
      await _controller.close();
      return code;
    });
  }

  final Process _process;
  final StreamController<String> _controller = StreamController<String>();
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  late final Future<int> _exitCode;
  bool _running = true;

  @override
  final Uri url;

  @override
  Stream<String> get output => _controller.stream;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  bool get running => _running;

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    if (Platform.isWindows) {
      await Process.run('taskkill.exe', <String>[
        '/PID',
        '${_process.pid}',
        '/T',
        '/F',
      ], runInShell: false).timeout(
        const Duration(seconds: 5),
        onTimeout: () => ProcessResult(0, -1, '', ''),
      );
    } else {
      _process.kill(ProcessSignal.sigterm);
    }
    await _exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}
