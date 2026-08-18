import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class GitRepositorySnapshot {
  const GitRepositorySnapshot({
    required this.root,
    required this.branch,
    required this.status,
    required this.diff,
    required this.log,
  });

  final String root;
  final String branch;
  final String status;
  final String diff;
  final String log;
}

class GitReferenceComparison {
  const GitReferenceComparison({
    required this.root,
    required this.baseRef,
    required this.targetRef,
    required this.baseCommit,
    required this.targetCommit,
    required this.summary,
    required this.changedFiles,
    required this.diff,
  });

  final String root;
  final String baseRef;
  final String targetRef;
  final String baseCommit;
  final String targetCommit;
  final String summary;
  final String changedFiles;
  final String diff;
}

abstract final class GitRepositoryService {
  static const int _maxOutputBytes = 2 * 1024 * 1024;

  static String get bundledExecutable => _resolveGitExecutable();

  static Future<GitRepositorySnapshot> inspect(String directory) async {
    final String path = directory.trim();
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('请选择存在的项目目录');
    }
    final String root = (await _git(path, <String>[
      'rev-parse',
      '--show-toplevel',
    ])).trim();
    final String status = await _git(root, <String>[
      'status',
      '--porcelain=v1',
      '--branch',
      '--untracked-files=all',
    ]);
    final String firstLine = status.split('\n').firstOrNull ?? '';
    final String branch = firstLine.startsWith('## ')
        ? firstLine.substring(3).trim()
        : 'detached / unknown';
    final List<String> diffs = await Future.wait(<Future<String>>[
      _git(root, <String>[
        'diff',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=3',
        '--',
      ]),
      _git(root, <String>[
        'diff',
        '--cached',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=3',
        '--',
      ]),
    ]);
    String log;
    try {
      log = await _git(root, <String>[
        'log',
        '-n',
        '30',
        '--date=short',
        '--pretty=format:%h%x09%ad%x09%s',
      ]);
    } on FormatException catch (error) {
      if (error.message.contains('does not have any commits yet')) {
        log = '仓库尚无提交';
      } else {
        rethrow;
      }
    }
    final String unstaged = diffs[0].trim();
    final String staged = diffs[1].trim();
    final String combinedDiff = <String>[
      if (staged.isNotEmpty) '=== 已暂存 ===\n$staged',
      if (unstaged.isNotEmpty) '=== 未暂存 ===\n$unstaged',
    ].join('\n\n');
    return GitRepositorySnapshot(
      root: root,
      branch: branch,
      status: status.trim().isEmpty ? '工作区干净' : status.trim(),
      diff: combinedDiff.isEmpty ? '没有文本差异' : combinedDiff,
      log: log.trim().isEmpty ? '仓库尚无提交' : log.trim(),
    );
  }

  static Future<GitReferenceComparison> compareRefs(
    String directory, {
    required String baseRef,
    required String targetRef,
  }) async {
    final String root = await _repositoryRoot(directory);
    final String base = _requiredRef(baseRef, '基准版本');
    final String target = _requiredRef(targetRef, '目标版本');
    final List<String> commits = await Future.wait(<Future<String>>[
      _git(root, <String>['rev-parse', '--verify', '$base^{commit}']),
      _git(root, <String>['rev-parse', '--verify', '$target^{commit}']),
    ]);
    final List<String> details = await Future.wait(<Future<String>>[
      _git(root, <String>[
        'diff',
        '--stat',
        '--no-ext-diff',
        base,
        target,
        '--',
      ]),
      _git(root, <String>[
        'diff',
        '--name-status',
        '--no-renames',
        '--no-ext-diff',
        base,
        target,
        '--',
      ]),
      _git(root, <String>[
        'diff',
        '--no-renames',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=3',
        base,
        target,
        '--',
      ]),
    ]);
    return GitReferenceComparison(
      root: root,
      baseRef: base,
      targetRef: target,
      baseCommit: commits[0].trim(),
      targetCommit: commits[1].trim(),
      summary: details[0].trim().isEmpty ? '两个版本没有差异' : details[0].trim(),
      changedFiles: details[1].trim().isEmpty ? '没有变化的文件' : details[1].trim(),
      diff: details[2].trim().isEmpty ? '没有文本差异' : details[2].trim(),
    );
  }

  /// Creates a local safety branch without switching the current checkout.
  static Future<String> createLocalBranch(
    String directory, {
    required String name,
    String startPoint = 'HEAD',
  }) async {
    final String root = await _repositoryRoot(directory);
    final String branch = name.trim();
    if (branch.isEmpty) throw const FormatException('请输入本地分支名称');
    await _git(root, <String>['check-ref-format', '--branch', branch]);
    final String start = _requiredRef(startPoint, '起点版本');
    await _git(root, <String>['rev-parse', '--verify', '$start^{commit}']);
    await _git(root, <String>['branch', '--', branch, start]);
    return branch;
  }

  static Future<String> _repositoryRoot(String directory) async {
    final String path = directory.trim();
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('请选择存在的项目目录');
    }
    return (await _git(path, <String>['rev-parse', '--show-toplevel'])).trim();
  }

  static String _requiredRef(String value, String label) {
    final String result = value.trim();
    if (result.isEmpty) throw FormatException('请输入$label');
    if (result.startsWith('-')) throw FormatException('$label不能以 - 开头');
    return result;
  }

  static Future<String> _git(String directory, List<String> arguments) async {
    final Process process;
    try {
      process = await Process.start(_resolveGitExecutable(), <String>[
        '--no-pager',
        '-C',
        directory,
        ...arguments,
      ], runInShell: false);
    } on ProcessException catch (error) {
      throw StateError('内置 Git 无法启动：${error.message}');
    }
    final Future<List<int>> stdout = _boundedBytes(process.stdout, process);
    final Future<List<int>> stderr = _boundedBytes(process.stderr, process);
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill();
      throw const FormatException('Git 命令超过 10 秒，已停止');
    }
    final String output = utf8.decode(await stdout, allowMalformed: true);
    final String error = utf8.decode(await stderr, allowMalformed: true).trim();
    if (exitCode != 0) {
      throw FormatException(error.isEmpty ? 'Git 命令失败（exit $exitCode）' : error);
    }
    return output;
  }

  static String _resolveGitExecutable() {
    final String separator = Platform.pathSeparator;
    final String executableDirectory = File(Platform.resolvedExecutable)
        .parent
        .path;
    final List<String> candidates = Platform.isWindows
        ? <String>[
            '$executableDirectory${separator}tools${separator}git'
                '${separator}cmd${separator}git.exe',
            '${Directory.current.path}${separator}native${separator}git'
                '${separator}windows${separator}runtime${separator}cmd'
                '${separator}git.exe',
          ]
        : <String>[
            '$executableDirectory$separator..${separator}Resources'
                '${separator}tools${separator}git${separator}bin'
                '${separator}git',
            '${Directory.current.path}${separator}native${separator}git'
                '${separator}macos${separator}runtime${separator}bin'
                '${separator}git',
          ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) return File(candidate).absolute.path;
    }
    throw StateError(
      '安装包缺少内置 Git 运行时，请重新安装 Vibekits。已检查：'
      '${candidates.join('；')}',
    );
  }

  static Future<List<int>> _boundedBytes(
    Stream<List<int>> source,
    Process process,
  ) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int length = 0;
    await for (final List<int> chunk in source) {
      length += chunk.length;
      if (length > _maxOutputBytes) {
        process.kill();
        throw const FormatException('Git 输出超过 2 MiB，已停止');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
