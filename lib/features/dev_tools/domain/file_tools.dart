import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'tool_result.dart';

/// 文件工具（docs/06 §6.4，DEV-004/007）。
abstract final class FileTools {
  static ToolResult fileHash(String path, String algorithm) {
    final File file = File(path.trim());
    if (!file.existsSync()) {
      return const ToolFailure('文件不存在');
    }
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
    } catch (e) {
      return ToolFailure('文件哈希失败：$e');
    }
  }

  /// 批量重命名计划：返回“旧路径|新名称”列表，只生成计划不写入。
  static ToolResult batchRenamePlan(
    String directory,
    String find,
    String replace,
  ) {
    final Directory dir = Directory(directory.trim());
    if (!dir.existsSync()) {
      return const ToolFailure('目录不存在');
    }
    final List<String> lines = <String>[];
    int conflicts = 0;
    final List<FileSystemEntity> files = dir
        .listSync(followLinks: false)
        .where(
          (FileSystemEntity e) =>
              FileSystemEntity.typeSync(e.path) == FileSystemEntityType.file,
        )
        .toList();
    for (final FileSystemEntity entity in files) {
      final File file = File(entity.path);
      final String oldName = file.uri.pathSegments.last;
      final String newName = find.isEmpty
          ? oldName
          : oldName.replaceAll(find, replace);
      if (newName != oldName) {
        final String newPath = '${dir.path}${Platform.pathSeparator}$newName';
        final bool conflict =
            File(newPath).existsSync() && newPath != file.path;
        if (conflict) conflicts++;
        lines.add('$oldName -> $newName${conflict ? '（冲突）' : ''}');
      }
    }
    if (lines.isEmpty) {
      return const ToolSuccess('无匹配文件');
    }
    return ToolSuccess(
      '${lines.length} 个文件将被重命名（冲突 $conflicts）:\n${lines.join('\n')}',
    );
  }
}
