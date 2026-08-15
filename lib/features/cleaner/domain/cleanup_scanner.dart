import 'dart:io';

/// 清理类别（docs/00 §4.1）。
enum CleanupCategory {
  userTemp('用户临时文件', false),
  browserCache('浏览器缓存', false),
  devCache('开发缓存', true),
  logs('日志/崩溃转储', false),
  emptyDirs('空目录', true),
  downloads('下载建议', true),
  recycleBin('回收站', true);

  const CleanupCategory(this.label, this.highRisk);

  final String label;
  final bool highRisk;
}

/// 清理候选项（只读扫描结果，不删除）。
class CleanupCandidate {
  const CleanupCandidate({
    required this.path,
    required this.size,
    required this.category,
    required this.reason,
    this.modified,
  });

  final String path;
  final int size;
  final CleanupCategory category;
  final String reason;
  final DateTime? modified;

  bool get highRisk => category.highRisk;
}

/// 清理扫描器（docs/00 §4.1，CLN-001）。
///
/// 只生成候选项，绝不删除；空目录按“删除后仍为空”才建议。
abstract final class CleanupScanner {
  static const int _maxEntries = 5000;
  static const int _maxDepth = 8;

  /// 扫描一个目录及其子目录，按 [category] 归类。
  static Future<List<CleanupCandidate>> scanDirectory(
    String root,
    CleanupCategory category, {
    int maxDepth = _maxDepth,
  }) async {
    final List<CleanupCandidate> candidates = <CleanupCandidate>[];
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      return candidates;
    }

    Future<void> walk(String path, int depth) async {
      if (depth > maxDepth || candidates.length >= _maxEntries) {
        return;
      }
      Directory current = Directory(path);
      try {
        await for (final FileSystemEntity entity in current.list(
          followLinks: false,
        )) {
          if (candidates.length >= _maxEntries) return;
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.link) {
            continue; // 不跟随符号链接/联接点
          }
          if (type == FileSystemEntityType.directory) {
            await walk(entity.path, depth + 1);
            // 目录为空且非根时，作为空目录候选。
            if (depth > 0 && Directory(entity.path).listSync().isEmpty) {
              candidates.add(
                CleanupCandidate(
                  path: entity.path,
                  size: 0,
                  category: category,
                  reason: '空目录',
                ),
              );
            }
          } else if (type == FileSystemEntityType.file) {
            final File file = File(entity.path);
            final int size = await file.length();
            final DateTime modified = await file.lastModified();
            candidates.add(
              CleanupCandidate(
                path: entity.path,
                size: size,
                category: category,
                reason: category.label,
                modified: modified,
              ),
            );
          }
        }
      } catch (_) {
        // 无权限或已删除：跳过。
      }
    }

    await walk(root, 0);
    return candidates;
  }

  /// 扫描用户临时目录。
  static Future<List<CleanupCandidate>> scanUserTemp() async {
    final String? temp = Platform.environment['TEMP'];
    if (temp == null) return <CleanupCandidate>[];
    return scanDirectory(temp, CleanupCategory.userTemp);
  }
}
