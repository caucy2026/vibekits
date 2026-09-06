import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum AgentCliTaskState { running, succeeded, failed, cancelled, timedOut }

class AgentCliProvider {
  const AgentCliProvider({
    required this.id,
    required this.name,
    required this.commands,
    required this.versionArguments,
    required this.nonInteractiveHint,
    required this.protocols,
    required this.redistribution,
  });

  final String id;
  final String name;
  final List<String> commands;
  final List<String> versionArguments;
  final String nonInteractiveHint;
  final List<String> protocols;
  final String redistribution;

  Map<String, Object?> toJson() => <String, Object?>{
    'providerId': id,
    'name': name,
    'commands': commands,
    'nonInteractiveHint': nonInteractiveHint,
    'protocols': protocols,
    'redistribution': redistribution,
  };
}

class AgentCliService {
  AgentCliService({
    Map<String, String> executableOverrides = const <String, String>{},
    String? runtimeToolRoot,
    Future<void> Function(int processId)? bindProcessTree,
    Future<void> Function(int processId)? releaseProcessTree,
  }) : _executableOverrides = executableOverrides,
       _runtimeToolRoot = runtimeToolRoot,
       _bindProcessTree = bindProcessTree,
       _releaseProcessTree = releaseProcessTree;

  static const List<AgentCliProvider> providers = <AgentCliProvider>[
    AgentCliProvider(
      id: 'codex',
      name: 'OpenAI Codex CLI',
      commands: <String>['codex'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'codex exec <prompt>',
      protocols: <String>['mcp', 'app-server', 'sdk'],
      redistribution: 'system_or_separately_verified_bundle',
    ),
    AgentCliProvider(
      id: 'claude',
      name: 'Claude Code',
      commands: <String>['claude'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'claude -p <prompt>',
      protocols: <String>['mcp'],
      redistribution: 'system_install_only',
    ),
    AgentCliProvider(
      id: 'copilot',
      name: 'GitHub Copilot CLI',
      commands: <String>['copilot'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'copilot -p <prompt>',
      protocols: <String>['mcp', 'acp'],
      redistribution: 'system_install_only',
    ),
    AgentCliProvider(
      id: 'cursor',
      name: 'Cursor Agent',
      commands: <String>['cursor-agent'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'inspect runtime help before execution',
      protocols: <String>[],
      redistribution: 'system_install_only',
    ),
    AgentCliProvider(
      id: 'gemini',
      name: 'Gemini CLI',
      commands: <String>['gemini'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'gemini -p <prompt> --output-format json',
      protocols: <String>['mcp', 'acp'],
      redistribution: 'system_or_separately_verified_bundle',
    ),
    AgentCliProvider(
      id: 'aider',
      name: 'Aider',
      commands: <String>['aider'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'aider --message <prompt>',
      protocols: <String>[],
      redistribution: 'system_or_separately_verified_bundle',
    ),
    AgentCliProvider(
      id: 'opencode',
      name: 'OpenCode',
      commands: <String>['opencode'],
      versionArguments: <String>['--version'],
      nonInteractiveHint: 'inspect runtime help before execution',
      protocols: <String>[],
      redistribution: 'system_or_separately_verified_bundle',
    ),
  ];

  static const int _maxOutputBytes = 262144;
  static const Duration _retention = Duration(minutes: 30);
  final Map<String, String> _executableOverrides;
  final String? _runtimeToolRoot;
  final Future<void> Function(int processId)? _bindProcessTree;
  final Future<void> Function(int processId)? _releaseProcessTree;
  final Map<String, _AgentCliTask> _tasks = <String, _AgentCliTask>{};
  int _sequence = 0;

  Future<Map<String, Object?>> catalog() async {
    _purgeExpiredTasks();
    return <String, Object?>{
      'platform': Platform.operatingSystem,
      'providers': <Map<String, Object?>>[
        for (final AgentCliProvider provider in providers)
          await inspect(provider.id),
      ],
    };
  }

  Future<Map<String, Object?>> inspect(String providerId) async {
    final AgentCliProvider provider = _provider(providerId);
    final _ResolvedExecutable? resolved = await _resolve(provider);
    if (resolved == null) {
      return <String, Object?>{
        ...provider.toJson(),
        'available': false,
        'source': 'unavailable',
      };
    }
    try {
      final ProcessResult result = await Process.run(
        resolved.path,
        provider.versionArguments,
        environment: _environment,
        runInShell: false,
      ).timeout(const Duration(seconds: 15));
      final String output = '${result.stdout}\n${result.stderr}'.trim();
      return <String, Object?>{
        ...provider.toJson(),
        'available': result.exitCode == 0,
        'source': resolved.source,
        'executable': resolved.path,
        'version': _bounded(_redact(output)),
        'exitCode': result.exitCode,
      };
    } on Object catch (error) {
      return <String, Object?>{
        ...provider.toJson(),
        'available': false,
        'source': resolved.source,
        'executable': resolved.path,
        'error': _bounded(_redact('$error')),
      };
    }
  }

  Future<Map<String, Object?>> execute(
    String providerId,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final Map<String, Object?> started = await startTask(
      providerId,
      arguments,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    final String taskId = started['taskId']! as String;
    final _AgentCliTask task = _tasks[taskId]!;
    await task.completed.future;
    return status(taskId);
  }

  Future<Map<String, Object?>> startTask(
    String providerId,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(hours: 1),
  }) async {
    _purgeExpiredTasks();
    final AgentCliProvider provider = _provider(providerId);
    _validateArguments(arguments);
    final String? directory = _validateWorkingDirectory(workingDirectory);
    final _ResolvedExecutable? resolved = await _resolve(provider);
    if (resolved == null) {
      throw FormatException('${provider.name} 未安装或未随 APP 提供');
    }
    final Process process = await Process.start(
      resolved.path,
      arguments,
      workingDirectory: directory,
      environment: _environment,
      runInShell: false,
    );
    await _bindProcessTree?.call(process.pid);
    final String taskId = _nextTaskId(provider.id);
    final _AgentCliTask task = _AgentCliTask(
      id: taskId,
      provider: provider,
      executable: resolved,
      arguments: List<String>.unmodifiable(arguments),
      workingDirectory: directory,
      process: process,
      startedAt: DateTime.now().toUtc(),
      timeout: timeout,
    );
    _tasks[taskId] = task;
    unawaited(_collect(task));
    return status(taskId);
  }

  Map<String, Object?> status(String taskId) {
    _purgeExpiredTasks();
    final _AgentCliTask? task = _tasks[taskId.trim()];
    if (task == null) throw const FormatException('taskId 不存在或已过期');
    return task.toJson();
  }

  Future<Map<String, Object?>> cancel(String taskId) async {
    _purgeExpiredTasks();
    final _AgentCliTask? task = _tasks[taskId.trim()];
    if (task == null) throw const FormatException('taskId 不存在或已过期');
    if (task.state != AgentCliTaskState.running) return task.toJson();
    task.cancelRequested = true;
    task.process.kill(ProcessSignal.sigkill);
    await task.completed.future;
    return task.toJson();
  }

  Future<void> _collect(_AgentCliTask task) async {
    final Future<void> stdoutDone = task.process.stdout
        .listen(task.stdout.add)
        .asFuture<void>();
    final Future<void> stderrDone = task.process.stderr
        .listen(task.stderr.add)
        .asFuture<void>();
    Timer? timer;
    if (task.timeout > Duration.zero) {
      timer = Timer(task.timeout, () {
        if (task.state == AgentCliTaskState.running) {
          task.timeoutRequested = true;
          task.process.kill(ProcessSignal.sigkill);
        }
      });
    }
    try {
      task.exitCode = await task.process.exitCode;
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
      task.state = task.cancelRequested
          ? AgentCliTaskState.cancelled
          : task.timeoutRequested
          ? AgentCliTaskState.timedOut
          : task.exitCode == 0
          ? AgentCliTaskState.succeeded
          : AgentCliTaskState.failed;
    } on Object catch (error) {
      task.stderr.add(utf8.encode('\n$error'));
      task.state = AgentCliTaskState.failed;
    } finally {
      timer?.cancel();
      task.completedAt = DateTime.now().toUtc();
      await _releaseProcessTree?.call(task.process.pid);
      if (!task.completed.isCompleted) task.completed.complete();
    }
  }

  Future<_ResolvedExecutable?> _resolve(AgentCliProvider provider) async {
    final String suffix = Platform.isWindows ? '.exe' : '';
    final List<_ResolvedExecutable> candidates = <_ResolvedExecutable>[
      if (_executableOverrides[provider.id]?.trim().isNotEmpty == true)
        _ResolvedExecutable(
          File(_executableOverrides[provider.id]!).absolute.path,
          'override',
        ),
      for (final String command in provider.commands)
        if (_runtimeToolRoot != null)
          _ResolvedExecutable(
            '${Directory(_runtimeToolRoot).absolute.path}${Platform.pathSeparator}'
                'agent-cli${Platform.pathSeparator}${provider.id}'
                '${Platform.pathSeparator}$command$suffix',
            'bundled',
          ),
      for (final String command in provider.commands)
        _ResolvedExecutable(
          '${Directory.current.path}${Platform.pathSeparator}native'
              '${Platform.pathSeparator}agent_cli${Platform.pathSeparator}${provider.id}'
              '${Platform.pathSeparator}$_platformName'
              '${Platform.pathSeparator}runtime${Platform.pathSeparator}bin'
              '${Platform.pathSeparator}$command$suffix',
          'bundled',
        ),
      for (final String command in provider.commands)
        ..._pathCandidates('$command$suffix'),
    ];
    for (final _ResolvedExecutable candidate in candidates) {
      if (await File(candidate.path).exists()) return candidate;
      if (Platform.isWindows && !candidate.path.endsWith('.cmd')) {
        final String cmdPath = candidate.path.replaceFirst(
          RegExp(r'\.exe$'),
          '.cmd',
        );
        if (await File(cmdPath).exists()) {
          return _ResolvedExecutable(cmdPath, candidate.source);
        }
      }
    }
    return null;
  }

  static Iterable<_ResolvedExecutable> _pathCandidates(
    String executable,
  ) sync* {
    final String? path = Platform.environment['PATH'];
    if (path == null) return;
    for (final String directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.trim().isEmpty) continue;
      yield _ResolvedExecutable(
        '${directory.trim()}${Platform.pathSeparator}$executable',
        'system',
      );
    }
  }

  static AgentCliProvider _provider(String id) {
    final String normalized = id.trim().toLowerCase();
    for (final AgentCliProvider provider in providers) {
      if (provider.id == normalized) return provider;
    }
    throw FormatException(
      'providerId 无效；可选值：${providers.map((AgentCliProvider item) => item.id).join(', ')}',
    );
  }

  static String? _validateWorkingDirectory(String? value) {
    final String path = (value ?? '').trim();
    if (path.isEmpty) return null;
    final Directory directory = Directory(path).absolute;
    if (!directory.existsSync()) {
      throw FormatException('workingDirectory不存在：${directory.path}');
    }
    return directory.path;
  }

  static void _validateArguments(List<String> arguments) {
    if (arguments.isEmpty || arguments.length > 128) {
      throw const FormatException('arguments 必须包含1到128个参数');
    }
    const Set<String> secretFlags = <String>{
      '--api-key',
      '--token',
      '--access-token',
      '--client-secret',
      '--password',
      '--with-token',
    };
    for (final String argument in arguments) {
      if (argument.isEmpty ||
          argument.length > 16384 ||
          argument.contains('\u0000') ||
          argument.contains('\n') ||
          argument.contains('\r')) {
        throw const FormatException('参数为空、过长或包含控制字符');
      }
      final String flag = argument.toLowerCase().split('=').first;
      if (secretFlags.contains(flag)) {
        throw FormatException('$flag 不允许通过MCP参数传入');
      }
    }
  }

  String _nextTaskId(String providerId) {
    _sequence += 1;
    return 'agent-cli-$providerId-${DateTime.now().microsecondsSinceEpoch}-$_sequence';
  }

  void _purgeExpiredTasks() {
    final DateTime cutoff = DateTime.now().toUtc().subtract(_retention);
    _tasks.removeWhere(
      (String _, _AgentCliTask task) =>
          task.completedAt != null && task.completedAt!.isBefore(cutoff),
    );
  }

  static Map<String, String> get _environment => <String, String>{
    ...Platform.environment,
    'CI': '1',
    'NO_COLOR': '1',
    'PAGER': '',
    'GH_PAGER': '',
    'GH_PROMPT_DISABLED': '1',
    'GH_NO_UPDATE_NOTIFIER': '1',
    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
    'DISABLE_AUTOUPDATER': '1',
  };

  static String get _platformName => Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.operatingSystem;

  static String _bounded(String value) => value.length <= _maxOutputBytes
      ? value
      : '${value.substring(0, _maxOutputBytes ~/ 2)}\n...[truncated]...\n'
            '${value.substring(value.length - (_maxOutputBytes ~/ 2))}';

  static String _redact(String value) => value
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{20,}'), '[REDACTED_TOKEN]')
      .replaceAll(RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'), '[REDACTED_TOKEN]')
      .replaceAll(RegExp(r'gh[pousr]_[A-Za-z0-9_]{20,}'), '[REDACTED_TOKEN]')
      .replaceAll(RegExp(r'github_pat_[A-Za-z0-9_]{20,}'), '[REDACTED_TOKEN]')
      .replaceAll(RegExp(r'AIza[A-Za-z0-9_-]{20,}'), '[REDACTED_TOKEN]');
}

class _ResolvedExecutable {
  const _ResolvedExecutable(this.path, this.source);

  final String path;
  final String source;
}

class _BoundedOutput {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int totalBytes = 0;
  bool truncated = false;

  void add(List<int> chunk) {
    totalBytes += chunk.length;
    final int remaining = AgentCliService._maxOutputBytes - _bytes.length;
    if (remaining <= 0) {
      truncated = true;
      return;
    }
    if (chunk.length > remaining) {
      _bytes.add(chunk.sublist(0, remaining));
      truncated = true;
    } else {
      _bytes.add(chunk);
    }
  }

  String get text => AgentCliService._redact(
    utf8.decode(_bytes.toBytes(), allowMalformed: true),
  );
}

class _AgentCliTask {
  _AgentCliTask({
    required this.id,
    required this.provider,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.process,
    required this.startedAt,
    required this.timeout,
  });

  final String id;
  final AgentCliProvider provider;
  final _ResolvedExecutable executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Process process;
  final DateTime startedAt;
  final Duration timeout;
  final _BoundedOutput stdout = _BoundedOutput();
  final _BoundedOutput stderr = _BoundedOutput();
  final Completer<void> completed = Completer<void>();
  AgentCliTaskState state = AgentCliTaskState.running;
  DateTime? completedAt;
  int? exitCode;
  bool cancelRequested = false;
  bool timeoutRequested = false;

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': id,
    'providerId': provider.id,
    'providerName': provider.name,
    'state': state.name,
    'running': state == AgentCliTaskState.running,
    'pid': process.pid,
    'source': executable.source,
    'executable': executable.path,
    'arguments': arguments,
    'workingDirectory': ?workingDirectory,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': ?completedAt?.toIso8601String(),
    'exitCode': ?exitCode,
    'stdout': stdout.text,
    'stderr': stderr.text,
    'stdoutBytes': stdout.totalBytes,
    'stderrBytes': stderr.totalBytes,
    'stdoutTruncated': stdout.truncated,
    'stderrTruncated': stderr.truncated,
  };
}
