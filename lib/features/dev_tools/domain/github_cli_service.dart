import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef GithubCliRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required String? workingDirectory,
      required Map<String, String> environment,
      required Duration timeout,
    });

/// Runs the bundled official GitHub CLI without invoking a command shell.
class GithubCliService {
  const GithubCliService({this.executable, this.runner = run});

  final String? executable;
  final GithubCliRunner runner;

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    required String? workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
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
      throw TimeoutException(
        'GitHub CLI执行超过 ${timeout.inSeconds} 秒，进程已终止',
        timeout,
      );
    }
  }

  Future<Map<String, Object?>> inspect() async {
    final String path = await resolveExecutable();
    final Map<String, Object?> result = await _invoke(
      path,
      const <String>['--version'],
      workingDirectory: null,
      timeout: const Duration(seconds: 15),
    );
    return <String, Object?>{
      'available': result['ok'],
      'executable': path,
      'version': '${result['stdout'] ?? ''}'.trim(),
      'upstream': 'https://github.com/cli/cli',
      'license': 'MIT',
      'bundled': true,
      'platform': Platform.operatingSystem,
      'architecture': _architecture,
    };
  }

  Future<Map<String, Object?>> authStatus({String? hostname}) {
    final String host = (hostname ?? '').trim();
    _validateHost(host);
    return execute(<String>[
      'auth',
      'status',
      if (host.isNotEmpty) ...<String>['--hostname', host],
    ], timeout: const Duration(seconds: 60));
  }

  Future<Map<String, Object?>> execute(
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _validateArguments(arguments);
    final String? directory = _validateWorkingDirectory(workingDirectory);
    return _invoke(
      await resolveExecutable(),
      arguments,
      workingDirectory: directory,
      timeout: timeout,
    );
  }

  Future<String> resolveExecutable() async {
    final String name = Platform.isWindows ? 'gh.exe' : 'gh';
    final String platform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : Platform.isLinux
        ? 'linux'
        : Platform.operatingSystem;
    final List<String> candidates = <String>[
      if (executable?.trim().isNotEmpty == true) executable!.trim(),
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}'
          'tools${Platform.pathSeparator}github-cli${Platform.pathSeparator}$name',
      '${Directory.current.path}${Platform.pathSeparator}native'
          '${Platform.pathSeparator}github_cli${Platform.pathSeparator}$platform'
          '${Platform.pathSeparator}runtime${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}$name',
    ];
    for (final String candidate in candidates) {
      final File file = File(candidate).absolute;
      if (await file.exists()) return file.path;
    }
    throw StateError(
      'GitHub CLI运行时缺失；请重新安装VibeKits或运行对应平台的准备脚本。已检查：${candidates.join('；')}',
    );
  }

  Future<Map<String, Object?>> _invoke(
    String path,
    List<String> arguments, {
    required String? workingDirectory,
    required Duration timeout,
  }) async {
    final ProcessResult result = await runner(
      path,
      arguments,
      workingDirectory: workingDirectory,
      environment: <String, String>{
        ...Platform.environment,
        'GH_PROMPT_DISABLED': '1',
        'GH_NO_UPDATE_NOTIFIER': '1',
        'GH_NO_EXTENSION_UPDATE_NOTIFIER': '1',
        'GH_PAGER': '',
        'PAGER': '',
        'NO_COLOR': '1',
        'DO_NOT_TRACK': '1',
      },
      timeout: timeout,
    );
    final String stdout = _redact('${result.stdout}');
    final String stderr = _redact('${result.stderr}');
    return <String, Object?>{
      'ok': result.exitCode == 0,
      'exitCode': result.exitCode,
      'arguments': arguments,
      'workingDirectory': ?workingDirectory,
      if (stdout.trim().isNotEmpty) 'stdout': _bounded(stdout),
      if (stderr.trim().isNotEmpty) 'stderr': _bounded(stderr),
    };
  }

  static String? _validateWorkingDirectory(String? value) {
    final String candidate = (value ?? '').trim();
    if (candidate.isEmpty) return null;
    final Directory directory = Directory(candidate).absolute;
    if (!directory.existsSync()) {
      throw FormatException('workingDirectory不存在：${directory.path}');
    }
    return directory.path;
  }

  static void _validateArguments(List<String> arguments) {
    if (arguments.isEmpty || arguments.length > 128) {
      throw const FormatException('arguments 必须包含1到128个参数');
    }
    for (final String argument in arguments) {
      if (argument.isEmpty ||
          argument.length > 16384 ||
          argument.contains('\u0000') ||
          argument.contains('\n') ||
          argument.contains('\r')) {
        throw const FormatException('参数为空、过长或包含控制字符');
      }
    }
    final List<String> normalized = arguments
        .map((String value) => value.toLowerCase())
        .toList(growable: false);
    if (normalized.length >= 2 &&
        normalized[0] == 'auth' &&
        normalized[1] == 'token') {
      throw const FormatException('禁止通过MCP读取GitHub认证令牌');
    }
    const Set<String> secretFlags = <String>{
      '--with-token',
      '--token',
      '--client-secret',
    };
    for (final String value in normalized) {
      if (secretFlags.contains(value.split('=').first)) {
        throw FormatException('${value.split('=').first} 不允许通过MCP参数传入');
      }
    }
  }

  static void _validateHost(String host) {
    if (host.isNotEmpty &&
        !RegExp(r'^[A-Za-z0-9.-]+(?::[0-9]+)?$').hasMatch(host)) {
      throw const FormatException('hostname格式无效');
    }
  }

  static String _bounded(String value) => value.length <= 262144
      ? value
      : '${value.substring(0, 131072)}\n...[truncated]...\n'
            '${value.substring(value.length - 131072)}';

  static String _redact(String value) => value
      .replaceAll(
        RegExp(r'gh[pousr]_[A-Za-z0-9_]{20,}'),
        '[REDACTED_GITHUB_TOKEN]',
      )
      .replaceAll(
        RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
        '[REDACTED_GITHUB_TOKEN]',
      );

  static String get _architecture => Platform.version.contains('arm64')
      ? 'arm64'
      : Platform.version.contains('aarch64')
      ? 'arm64'
      : 'amd64';
}
