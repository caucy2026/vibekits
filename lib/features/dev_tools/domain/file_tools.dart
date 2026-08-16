import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'tool_result.dart';

enum RenameLetterCase { keep, lower, upper }

class BatchRenameOptions {
  const BatchRenameOptions({
    this.find = '',
    this.replace = '',
    this.prefix = '',
    this.suffix = '',
    this.letterCase = RenameLetterCase.keep,
    this.addSequence = false,
    this.sequenceStart = 1,
    this.sequencePadding = 2,
  });

  final String find;
  final String replace;
  final String prefix;
  final String suffix;
  final RenameLetterCase letterCase;
  final bool addSequence;
  final int sequenceStart;
  final int sequencePadding;
}

class BatchRenameItem {
  const BatchRenameItem({
    required this.sourcePath,
    required this.oldName,
    required this.newName,
    this.issue,
  });

  final String sourcePath;
  final String oldName;
  final String newName;
  final String? issue;

  bool get willRename => issue == null && oldName != newName;
}

class BatchRenamePlan {
  const BatchRenamePlan({required this.directory, required this.items});

  final String directory;
  final List<BatchRenameItem> items;

  int get renameCount =>
      items.where((BatchRenameItem item) => item.willRename).length;
  int get issueCount =>
      items.where((BatchRenameItem item) => item.issue != null).length;
  bool get canExecute => renameCount > 0 && issueCount == 0;
}

class BatchRenameReport {
  const BatchRenameReport({
    required this.succeeded,
    required this.total,
    this.failure,
    this.rollbackFailure,
  });

  final int succeeded;
  final int total;
  final String? failure;
  final String? rollbackFailure;

  bool get isSuccess => failure == null && succeeded == total;

  String get summary {
    if (isSuccess) return '已重命名 $succeeded 个文件';
    final String rollback = rollbackFailure == null
        ? '已尝试恢复原文件名'
        : '恢复失败：$rollbackFailure';
    return '重命名失败：$failure\n已完成 $succeeded/$total；$rollback';
  }
}

/// 文件工具（docs/06 §6.4，DEV-004/007）。
abstract final class FileTools {
  static ToolResult fileHash(String path, String algorithm) {
    final File file = File(path.trim());
    if (!file.existsSync()) return const ToolFailure('文件不存在');
    try {
      final List<int> bytes = file.readAsBytesSync();
      final String hex = switch (algorithm) {
        'md5' => crypto.md5.convert(bytes).toString(),
        'sha1' => crypto.sha1.convert(bytes).toString(),
        'sha256' => crypto.sha256.convert(bytes).toString(),
        'sha512' => crypto.sha512.convert(bytes).toString(),
        _ => throw ArgumentError('不支持的算法'),
      };
      return ToolSuccess(hex);
    } catch (error) {
      return ToolFailure('文件哈希失败：$error');
    }
  }

  static BatchRenamePlan buildBatchRenamePlan(
    String directory,
    BatchRenameOptions options,
  ) {
    final Directory dir = Directory(directory.trim());
    if (!dir.existsSync()) {
      return BatchRenamePlan(
        directory: dir.path,
        items: const <BatchRenameItem>[],
      );
    }

    final List<FileSystemEntity> files =
        dir
            .listSync(followLinks: false)
            .where(
              (FileSystemEntity entity) =>
                  FileSystemEntity.typeSync(entity.path, followLinks: false) ==
                  FileSystemEntityType.file,
            )
            .toList()
          ..sort(
            (FileSystemEntity a, FileSystemEntity b) =>
                _fileName(a.path)
                    .toLowerCase()
                    .compareTo(_fileName(b.path).toLowerCase()),
          );

    final Set<String> sourcePaths = files
        .map((FileSystemEntity file) => _normalizedPath(file.path))
        .toSet();
    final Map<String, int> targetCounts = <String, int>{};
    final List<BatchRenameItem> draft = <BatchRenameItem>[];

    for (int index = 0; index < files.length; index++) {
      final FileSystemEntity entity = files[index];
      final String oldName = _fileName(entity.path);
      final String replacedName = options.find.isEmpty
          ? oldName
          : oldName.replaceAll(options.find, options.replace);
      final ({String stem, String extension}) parts = _splitFileName(
        replacedName,
      );
      String stem = parts.stem;
      stem = '${options.prefix}$stem${options.suffix}';
      stem = switch (options.letterCase) {
        RenameLetterCase.keep => stem,
        RenameLetterCase.lower => stem.toLowerCase(),
        RenameLetterCase.upper => stem.toUpperCase(),
      };
      if (options.addSequence) {
        final int number = options.sequenceStart + index;
        stem =
            '$stem${number.toString().padLeft(options.sequencePadding, '0')}';
      }
      final String newName = '$stem${parts.extension}';
      final String normalizedTarget = newName.toLowerCase();
      targetCounts.update(
        normalizedTarget,
        (int value) => value + 1,
        ifAbsent: () => 1,
      );
      draft.add(
        BatchRenameItem(
          sourcePath: entity.path,
          oldName: oldName,
          newName: newName,
          issue: _validateWindowsFileName(newName, dir.path),
        ),
      );
    }

    final List<BatchRenameItem> checked = draft
        .map((BatchRenameItem item) {
          String? issue = item.issue;
          final String targetPath =
              '${dir.path}${Platform.pathSeparator}${item.newName}';
          if (issue == null &&
              targetCounts[item.newName.toLowerCase()]! > 1 &&
              item.oldName != item.newName) {
            issue = '多个文件会得到相同名称';
          }
          if (issue == null &&
              item.oldName != item.newName &&
              FileSystemEntity.typeSync(targetPath, followLinks: false) !=
                  FileSystemEntityType.notFound &&
              !sourcePaths.contains(_normalizedPath(targetPath))) {
            issue = '目标名称已存在';
          }
          return BatchRenameItem(
            sourcePath: item.sourcePath,
            oldName: item.oldName,
            newName: item.newName,
            issue: issue,
          );
        })
        .toList(growable: false);

    return BatchRenamePlan(directory: dir.path, items: checked);
  }

  /// 两阶段改名避免 A→B、B→C 等目标互相占用；失败时尽力恢复原名。
  static BatchRenameReport executeBatchRename(BatchRenamePlan plan) {
    final List<BatchRenameItem> changes = plan.items
        .where((BatchRenameItem item) => item.willRename)
        .toList(growable: false);
    if (!plan.canExecute) {
      return BatchRenameReport(
        succeeded: 0,
        total: changes.length,
        failure: plan.issueCount > 0 ? '计划包含冲突或非法名称' : '没有需要重命名的文件',
      );
    }

    final String token = DateTime.now().microsecondsSinceEpoch.toString();
    final List<({BatchRenameItem item, String temporaryPath})> staged =
        <({BatchRenameItem item, String temporaryPath})>[];
    int completed = 0;
    try {
      for (int index = 0; index < changes.length; index++) {
        final BatchRenameItem item = changes[index];
        final String temporaryPath =
            '${plan.directory}${Platform.pathSeparator}.vibekits-rename-$token-$index.tmp';
        File(item.sourcePath).renameSync(temporaryPath);
        staged.add((item: item, temporaryPath: temporaryPath));
      }
      for (final ({BatchRenameItem item, String temporaryPath}) entry
          in staged) {
        final String target =
            '${plan.directory}${Platform.pathSeparator}${entry.item.newName}';
        File(entry.temporaryPath).renameSync(target);
        completed++;
      }
      return BatchRenameReport(succeeded: completed, total: changes.length);
    } catch (error) {
      String? rollbackFailure;
      final List<({BatchRenameItem item, String rollbackPath})> rollback =
          <({BatchRenameItem item, String rollbackPath})>[];
      // 先把所有现存文件移出最终命名空间，避免 A→B、B→C 恢复时互相占位。
      for (int index = 0; index < staged.length; index++) {
        final ({BatchRenameItem item, String temporaryPath}) entry =
            staged[index];
        final String target =
            '${plan.directory}${Platform.pathSeparator}${entry.item.newName}';
        final String currentPath = File(entry.temporaryPath).existsSync()
            ? entry.temporaryPath
            : target;
        if (!File(currentPath).existsSync()) continue;
        final String rollbackPath =
            '${plan.directory}${Platform.pathSeparator}.vibekits-rollback-$token-$index.tmp';
        try {
          File(currentPath).renameSync(rollbackPath);
          rollback.add((item: entry.item, rollbackPath: rollbackPath));
        } catch (rollbackError) {
          rollbackFailure ??= rollbackError.toString();
        }
      }
      for (final ({BatchRenameItem item, String rollbackPath}) entry
          in rollback) {
        try {
          File(entry.rollbackPath).renameSync(entry.item.sourcePath);
        } catch (rollbackError) {
          rollbackFailure ??= rollbackError.toString();
        }
      }
      return BatchRenameReport(
        succeeded: completed,
        total: changes.length,
        failure: error.toString(),
        rollbackFailure: rollbackFailure,
      );
    }
  }

  /// 兼容通用工具调用，实际界面使用结构化预览与确认执行。
  static ToolResult batchRenamePlan(
    String directory,
    String find,
    String replace,
  ) {
    final Directory dir = Directory(directory.trim());
    if (!dir.existsSync()) return const ToolFailure('目录不存在');
    final BatchRenamePlan plan = buildBatchRenamePlan(
      directory,
      BatchRenameOptions(find: find, replace: replace),
    );
    final List<BatchRenameItem> changes = plan.items
        .where((BatchRenameItem item) => item.oldName != item.newName)
        .toList(growable: false);
    if (changes.isEmpty) return const ToolSuccess('无匹配文件');
    return ToolSuccess(
      '${changes.length} 个文件将被重命名（问题 ${plan.issueCount}）：\n'
      '${changes.map((BatchRenameItem item) => '${item.oldName} -> ${item.newName}${item.issue == null ? '' : '（${item.issue}）'}').join('\n')}',
    );
  }

  static String _fileName(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static ({String stem, String extension}) _splitFileName(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) return (stem: name, extension: '');
    return (stem: name.substring(0, dot), extension: name.substring(dot));
  }

  static String _normalizedPath(String path) =>
      File(path).absolute.path.toLowerCase();

  static String? _validateWindowsFileName(String name, String directory) {
    if (name.isEmpty || name == '.' || name == '..') return '文件名不能为空';
    if (RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(name)) {
      return '包含 Windows 非法字符';
    }
    if (name.endsWith('.') || name.endsWith(' ')) return '不能以空格或句点结尾';
    final String base = name.split('.').first.toUpperCase();
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(base)) {
      return '属于 Windows 保留名称';
    }
    final String path = '$directory${Platform.pathSeparator}$name';
    if (path.codeUnits.length >= 260) return '完整路径超过 259 个字符';
    return null;
  }
}
