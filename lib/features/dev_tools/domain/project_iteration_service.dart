import 'dart:io';

typedef IterationProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Duration timeout,
});

/// A constrained build gate for Harness-driven iterations.
///
/// Harness may edit source through its normal workspace permission model, then
/// call this service to prove registration, analyze, test and build. It never
/// installs the resulting binary over the running APP and never invokes a
/// shell; releasing an update remains an explicit user-approved operation.
class ProjectIterationService {
  ProjectIterationService({IterationProcessRunner? runner})
    : _runner = runner ?? _run;

  final IterationProcessRunner _runner;

  Future<Map<String, Object?>> inspect(String workspace) async {
    final Directory root = _workspace(workspace);
    final File pubspec = File(
      '${root.path}${Platform.pathSeparator}pubspec.yaml',
    );
    final File registry = File(
      '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}'
      'features${Platform.pathSeparator}dev_tools${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}tool_registry.dart',
    );
    final File bridge = File(
      '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}'
      'features${Platform.pathSeparator}dev_tools${Platform.pathSeparator}'
      'domain${Platform.pathSeparator}harness_tool_bridge.dart',
    );
    return <String, Object?>{
      'workspace': root.path,
      'pubspec': pubspec.path,
      'toolRegistry': registry.path,
      'toolBridge': bridge.path,
      'ready':
          await pubspec.exists() &&
          await registry.exists() &&
          await bridge.exists(),
      'workflow': const <String>[
        '在 tool_registry.dart 登记描述、使用场景和 Harness IDs',
        '实现领域服务并在 harness_tool_bridge.dart 接入执行器',
        '运行 project.build 的 registration 门禁、Analyze 与测试',
        '生成目标平台 Release 产物',
        '人工验收后再提交、发布或安装，运行中的 APP 不自覆盖',
      ],
    };
  }

  Future<Map<String, Object?>> build({
    required String workspace,
    required String target,
    String flutterExecutable = '',
    bool runTests = true,
  }) async {
    final Directory root = _workspace(workspace);
    final String flutter = _flutterExecutable(flutterExecutable);
    final String normalizedTarget = target.trim().toLowerCase();
    if (!<String>{'windows', 'android', 'macos'}.contains(normalizedTarget)) {
      throw const FormatException('target 仅支持 windows、android、macos');
    }
    if (normalizedTarget == 'windows' && !Platform.isWindows ||
        normalizedTarget == 'macos' && !Platform.isMacOS) {
      throw StateError('$normalizedTarget Release 必须在对应桌面系统构建');
    }
    final List<Map<String, Object?>> steps = <Map<String, Object?>>[];
    await _step(
      steps,
      flutter,
      <String>['analyze'],
      root.path,
      const Duration(minutes: 8),
    );
    if (runTests) {
      await _step(
        steps,
        flutter,
        <String>[
          'test',
          'test/harness_capability_catalog_test.dart',
          'test/harness_tool_bridge_test.dart',
        ],
        root.path,
        const Duration(minutes: 12),
      );
    }
    final List<String> buildArguments = switch (normalizedTarget) {
      'windows' => <String>['build', 'windows', '--release'],
      'android' => <String>[
        'build',
        'apk',
        '--release',
        '--target-platform',
        'android-arm64',
      ],
      'macos' => <String>['build', 'macos', '--release'],
      _ => throw StateError('unreachable'),
    };
    await _step(
      steps,
      flutter,
      buildArguments,
      root.path,
      const Duration(minutes: 30),
    );
    return <String, Object?>{
      'workspace': root.path,
      'target': normalizedTarget,
      'success': true,
      'steps': steps,
      'artifact': switch (normalizedTarget) {
        'windows' =>
          '${root.path}/build/windows/x64/runner/Release/vibekits.exe',
        'android' =>
          '${root.path}/build/app/outputs/flutter-apk/app-release.apk',
        'macos' =>
          '${root.path}/build/macos/Build/Products/Release/Vibekits.app',
        _ => '',
      },
      'installPolicy': '产物只生成到 build；必须经用户批准和验收后才能替换或安装。',
    };
  }

  Future<void> _step(
    List<Map<String, Object?>> steps,
    String executable,
    List<String> arguments,
    String workspace,
    Duration timeout,
  ) async {
    final Stopwatch watch = Stopwatch()..start();
    final ProcessResult result = await _runner(
      executable,
      arguments,
      workingDirectory: workspace,
      timeout: timeout,
    );
    watch.stop();
    final Map<String, Object?> step = <String, Object?>{
      'command': <String>[executable, ...arguments],
      'exitCode': result.exitCode,
      'durationMs': watch.elapsedMilliseconds,
      'stdoutTail': _tail('${result.stdout}'),
      'stderrTail': _tail('${result.stderr}'),
    };
    steps.add(step);
    if (result.exitCode != 0) {
      throw StateError('迭代门禁失败：${arguments.join(' ')}\n${step['stderrTail']}');
    }
  }

  static Directory _workspace(String raw) {
    final Directory root = Directory(raw.trim()).absolute;
    if (raw.trim().isEmpty || !root.existsSync()) {
      throw const FormatException('工作区不存在');
    }
    if (!File('${root.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      throw const FormatException('工作区不是 Flutter 项目');
    }
    return root;
  }

  static String _flutterExecutable(String requested) {
    if (requested.trim().isNotEmpty) {
      final File file = File(requested.trim());
      if (!file.isAbsolute || !file.existsSync()) {
        throw const FormatException('指定 Flutter 可执行文件不存在');
      }
      return file.path;
    }
    final String? root = Platform.environment['FLUTTER_ROOT'];
    if (root != null && root.trim().isNotEmpty) {
      final String path =
          '$root${Platform.pathSeparator}bin${Platform.pathSeparator}'
          '${Platform.isWindows ? 'flutter.bat' : 'flutter'}';
      if (File(path).existsSync()) return path;
    }
    return Platform.isWindows ? 'flutter.bat' : 'flutter';
  }

  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Duration timeout,
  }) => Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  ).timeout(timeout);

  static String _tail(String value) {
    const int max = 4000;
    return value.length <= max ? value : value.substring(value.length - max);
  }
}
