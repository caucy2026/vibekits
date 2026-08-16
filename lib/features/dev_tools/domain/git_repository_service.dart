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

abstract final class GitRepositoryService {
  static const int _maxOutputBytes = 2 * 1024 * 1024;

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

  static Future<String> _git(String directory, List<String> arguments) async {
    final Process process;
    try {
      process = await Process.start('git', <String>[
        '-C',
        directory,
        ...arguments,
      ], runInShell: false);
    } on ProcessException catch (error) {
      throw StateError('未找到 Git：${error.message}');
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
