import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef LarkCliRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required Duration timeout,
});

class LarkCliService {
  const LarkCliService({
    this.executable,
    this.configDirectory,
    this.runner = run,
  });

  final String? executable;
  final String? configDirectory;
  final LarkCliRunner runner;

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      environment: environment,
      runInShell: false,
    );
    final Future<String> stdout = process.stdout.transform(utf8.decoder).join();
    final Future<String> stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final int exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await stdout;
      await stderr;
      throw TimeoutException('飞书CLI执行超过 ${timeout.inSeconds} 秒，进程已终止', timeout);
    }
  }

  Future<Map<String, Object?>> inspect() async {
    final String path = await resolveExecutable();
    final Map<String, Object?> result = await _invoke(path, const <String>[
      '--version',
    ], timeout: const Duration(seconds: 15));
    return <String, Object?>{
      'available': result['exitCode'] == 0,
      'executable': path,
      'version': '${result['stdout'] ?? ''}'.trim(),
      'upstream': 'https://github.com/larksuite/cli',
      'license': 'MIT',
      'jsonContract': 'stdout success / stderr typed failure',
    };
  }

  Future<Map<String, Object?>> authStatus() async => execute(const <String>[
    'auth',
    'status',
  ], timeout: const Duration(seconds: 60));

  Future<Map<String, Object?>> schema(String command) async {
    final List<String> path = command
        .trim()
        .split(RegExp(r'\s+'))
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    if (path.length > 8 || path.any((String value) => !_safeToken(value))) {
      throw const FormatException(
        'command 必须是最多8段的命令路径，例如 calendar.events.list',
      );
    }
    return execute(<String>['schema', if (path.isNotEmpty) path.join('.')]);
  }

  Future<Map<String, Object?>> execute(
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _validateArguments(arguments);
    return _invoke(await resolveExecutable(), arguments, timeout: timeout);
  }

  Future<String> resolveExecutable() async {
    final String name = Platform.isWindows ? 'lark-cli.exe' : 'lark-cli';
    final List<String> candidates = <String>[
      if (executable?.trim().isNotEmpty == true) executable!.trim(),
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}'
          'tools${Platform.pathSeparator}lark-cli${Platform.pathSeparator}$name',
      '${Directory.current.path}${Platform.pathSeparator}.cache'
          '${Platform.pathSeparator}lark-cli${Platform.pathSeparator}$name',
      '${Directory.current.path}${Platform.pathSeparator}native'
          '${Platform.pathSeparator}lark_cli${Platform.pathSeparator}'
          '${Platform.isWindows ? 'windows' : 'macos'}'
          '${Platform.pathSeparator}runtime${Platform.pathSeparator}$name',
    ];
    for (final String candidate in candidates) {
      final File file = File(candidate).absolute;
      if (await file.exists()) return file.path;
    }
    throw StateError('飞书CLI运行时缺失；请先执行项目的Lark CLI运行时准备脚本');
  }

  Future<Map<String, Object?>> _invoke(
    String path,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final String config = configDirectory?.trim().isNotEmpty == true
        ? Directory(configDirectory!).absolute.path
        : '${Directory.current.path}${Platform.pathSeparator}.runtime-cache'
              '${Platform.pathSeparator}lark-cli-config';
    await Directory(config).create(recursive: true);
    final ProcessResult result = await runner(
      path,
      arguments,
      environment: <String, String>{
        ...Platform.environment,
        'LARKSUITE_CLI_CONFIG_DIR': config,
        'LARKSUITE_CLI_NO_UPDATE_NOTIFIER': '1',
        'LARKSUITE_CLI_NO_SKILLS_NOTIFIER': '1',
      },
      timeout: timeout,
    );
    final String stdout = '${result.stdout}';
    final String stderr = '${result.stderr}';
    final Object? envelope = _decodeEnvelope(
      result.exitCode == 0 ? stdout : stderr,
    );
    return <String, Object?>{
      'exitCode': result.exitCode,
      'ok': result.exitCode == 0,
      'arguments': arguments,
      'envelope': ?envelope,
      if (stdout.trim().isNotEmpty) 'stdout': _bounded(stdout),
      if (stderr.trim().isNotEmpty) 'stderr': _bounded(stderr),
      'configDirectory': config,
    };
  }

  static Object? _decodeEnvelope(String value) {
    final String trimmed = value.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
  }

  static String _bounded(String value) => value.length <= 65536
      ? value
      : '${value.substring(0, 32768)}\n...[truncated]...\n${value.substring(value.length - 32768)}';

  static bool _safeToken(String value) =>
      RegExp(r'^[A-Za-z0-9_+.-]+$').hasMatch(value);

  static void _validateArguments(List<String> arguments) {
    if (arguments.isEmpty || arguments.length > 64) {
      throw const FormatException('arguments 必须包含1到64个参数');
    }
    const Set<String> forbidden = <String>{
      '--app-secret',
      '--access-token',
      '--refresh-token',
      '--tenant-access-token',
      '--user-access-token',
    };
    for (final String argument in arguments) {
      if (argument.isEmpty ||
          argument.length > 16384 ||
          argument.contains('\u0000') ||
          argument.contains('\n') ||
          argument.contains('\r')) {
        throw const FormatException('参数为空、过长或包含控制字符');
      }
      final String flag = argument.split('=').first.toLowerCase();
      if (forbidden.contains(flag)) {
        throw FormatException('$flag 不允许通过MCP参数传入；请使用官方配置和OAuth流程');
      }
    }
  }
}
