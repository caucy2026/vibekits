import 'dart:io';

import 'cleanup_task.dart';
import 'cleanup_targets.dart';
import 'cleanup_file_identity.dart';
import 'recycle_bin_service.dart';

enum CleanupRiskLevel {
  safe('推荐', false),
  cautious('需确认', true),
  systemManaged('系统管理', true);

  const CleanupRiskLevel(this.label, this.highRisk);

  final String label;
  final bool highRisk;
}

/// 清理类别（docs/00 §4.1）。
enum CleanupCategory {
  userTemp('用户临时文件', false),
  windowsTemp('Windows 临时目录', true),
  browserCache('浏览器缓存', false),
  applicationCache('应用缓存', false),
  systemCache('系统缓存', false),
  devCache('开发缓存', true),
  pluginCache('插件下载缓存', false),
  pluginResidual('旧版本插件', true),
  debugArtifacts('调试临时文件', false),
  logs('日志/崩溃转储', false),
  discoveredTransient('智能发现的缓存/日志', true),
  emptyDirs('空目录', true),
  downloads('下载建议', true),
  duplicateFiles('重复文件', true),
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
    this.identity,
    this.sourceLabel,
    this.riskLevel = CleanupRiskLevel.safe,
    this.impactNote = '',
  });

  final String path;
  final int size;
  final CleanupCategory category;
  final String reason;
  final DateTime? modified;
  final CleanupFileIdentity? identity;
  final String? sourceLabel;
  final CleanupRiskLevel riskLevel;
  final String impactNote;

  bool get highRisk => category.highRisk || riskLevel.highRisk;

  bool get allowsPermanentFallback =>
      switch (category) {
        CleanupCategory.browserCache ||
        CleanupCategory.applicationCache ||
        CleanupCategory.systemCache ||
        CleanupCategory.devCache ||
        CleanupCategory.pluginCache ||
        CleanupCategory.debugArtifacts ||
        CleanupCategory.logs => true,
        CleanupCategory.discoveredTransient => false,
        _ => false,
      } &&
      riskLevel == CleanupRiskLevel.safe;

  bool get defaultSelected {
    if (highRisk || reason == '空目录') return false;
    if (category == CleanupCategory.browserCache ||
        category == CleanupCategory.applicationCache ||
        category == CleanupCategory.systemCache ||
        category == CleanupCategory.pluginCache ||
        category == CleanupCategory.logs) {
      return true;
    }
    if (category == CleanupCategory.debugArtifacts && modified != null) {
      return DateTime.now().difference(modified!).inHours >= 24;
    }
    if (category == CleanupCategory.userTemp && modified != null) {
      return DateTime.now().difference(modified!).inHours >= 24;
    }
    return false;
  }
}

class CleanupScanProgress {
  const CleanupScanProgress({
    required this.currentPath,
    required this.visitedEntries,
    required this.candidateCount,
    required this.candidateBytes,
  });

  final String currentPath;
  final int visitedEntries;
  final int candidateCount;
  final int candidateBytes;
}

class CleanupScanResult {
  const CleanupScanResult({
    required this.candidates,
    required this.cancelled,
    required this.unreadablePaths,
    this.visitedEntries = 0,
    this.candidateBytes = 0,
  });

  final List<CleanupCandidate> candidates;
  final bool cancelled;
  final int unreadablePaths;
  final int visitedEntries;
  final int candidateBytes;
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
    int maxEntries = _maxEntries,
  }) async {
    final CleanupScanResult result = await scanDirectoryWithProgress(
      root,
      category,
      maxDepth: maxDepth,
      maxEntries: maxEntries,
    );
    return result.candidates;
  }

  static Future<CleanupScanResult> scanDirectoryWithProgress(
    String root,
    CleanupCategory category, {
    int maxDepth = _maxDepth,
    int maxEntries = _maxEntries,
    CleanupCancellationToken? cancellationToken,
    void Function(CleanupScanProgress progress)? onProgress,
    String? sourceLabel,
    int minimumAgeHours = 0,
    int minimumSizeBytes = 0,
    List<String> includePatterns = const <String>[],
    List<String> excludePatterns = const <String>[],
    CleanupRiskLevel riskLevel = CleanupRiskLevel.safe,
    String impactNote = '',
  }) async {
    final CleanupCancellationToken token =
        cancellationToken ?? CleanupCancellationToken();
    final List<CleanupCandidate> candidates = <CleanupCandidate>[];
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      return CleanupScanResult(
        candidates: candidates,
        cancelled: false,
        unreadablePaths: 0,
        visitedEntries: 0,
        candidateBytes: 0,
      );
    }

    int visited = 0;
    int candidateBytes = 0;
    int unreadable = 0;
    String currentPath = root;
    final Stopwatch progressClock = Stopwatch()..start();

    void report({bool force = false}) {
      if (onProgress == null ||
          (!force && progressClock.elapsedMilliseconds < 100)) {
        return;
      }
      progressClock.reset();
      onProgress(
        CleanupScanProgress(
          currentPath: currentPath,
          visitedEntries: visited,
          candidateCount: candidates.length,
          candidateBytes: candidateBytes,
        ),
      );
    }

    Future<void> walk(String path, int depth) async {
      if (token.isCancelled ||
          depth > maxDepth ||
          candidates.length >= maxEntries) {
        return;
      }
      final Directory current = Directory(path);
      try {
        await for (final FileSystemEntity entity in current.list(
          followLinks: false,
        )) {
          if (token.isCancelled || candidates.length >= maxEntries) return;
          currentPath = entity.path;
          visited++;
          report();
          if (visited % 8 == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.link) {
            continue; // 不跟随符号链接/联接点
          }
          if (type == FileSystemEntityType.directory) {
            await walk(entity.path, depth + 1);
            if (token.isCancelled) return;
            // 目录为空且非根时，作为空目录候选。
            if (depth > 0 &&
                includePatterns.isEmpty &&
                minimumAgeHours == 0 &&
                Directory(entity.path).listSync().isEmpty) {
              candidates.add(
                CleanupCandidate(
                  path: entity.path,
                  size: 0,
                  category: category,
                  reason: '空目录',
                  identity: CleanupFileIdentity.read(entity.path),
                  sourceLabel: sourceLabel,
                  riskLevel: riskLevel,
                  impactNote: impactNote,
                ),
              );
            }
          } else if (type == FileSystemEntityType.file) {
            final File file = File(entity.path);
            final int size = await file.length();
            if (size < minimumSizeBytes) continue;
            final DateTime modified = await file.lastModified();
            final String name = _baseName(entity.path).toLowerCase();
            if (includePatterns.isNotEmpty &&
                !includePatterns.any(
                  (String pattern) => _wildcardMatches(name, pattern),
                )) {
              continue;
            }
            if (excludePatterns.any(
              (String pattern) => _wildcardMatches(name, pattern),
            )) {
              continue;
            }
            if (minimumAgeHours > 0 &&
                DateTime.now().difference(modified).inHours < minimumAgeHours) {
              continue;
            }
            candidateBytes += size;
            candidates.add(
              CleanupCandidate(
                path: entity.path,
                size: size,
                category: category,
                reason: sourceLabel ?? category.label,
                modified: modified,
                identity: CleanupFileIdentity.read(entity.path),
                sourceLabel: sourceLabel,
                riskLevel: riskLevel,
                impactNote: impactNote,
              ),
            );
          }
        }
      } catch (_) {
        // 无权限或已删除：跳过。
        unreadable++;
      }
    }

    await walk(root, 0);
    report(force: true);
    return CleanupScanResult(
      candidates: candidates,
      cancelled: token.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visited,
      candidateBytes: candidateBytes,
    );
  }

  /// 扫描用户临时目录。
  static Future<List<CleanupCandidate>> scanUserTemp() async {
    final String? temp = Platform.environment['TEMP'];
    if (temp == null) return <CleanupCandidate>[];
    return scanDirectory(temp, CleanupCategory.userTemp);
  }

  static Future<CleanupScanResult> scanUserTempWithProgress({
    CleanupCancellationToken? cancellationToken,
    void Function(CleanupScanProgress progress)? onProgress,
  }) async {
    final String? temp = Platform.environment['TEMP'];
    if (temp == null) {
      return const CleanupScanResult(
        candidates: <CleanupCandidate>[],
        cancelled: false,
        unreadablePaths: 0,
        visitedEntries: 0,
        candidateBytes: 0,
      );
    }
    return scanDirectoryWithProgress(
      temp,
      CleanupCategory.userTemp,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }

  static Future<CleanupScanResult> scanTargets(
    List<CleanupScanTarget> targets, {
    CleanupCancellationToken? cancellationToken,
    void Function(CleanupScanProgress progress)? onProgress,
  }) async {
    final CleanupCancellationToken token =
        cancellationToken ?? CleanupCancellationToken();
    final Map<String, CleanupCandidate> candidates =
        <String, CleanupCandidate>{};
    int visitedOffset = 0;
    int bytesOffset = 0;
    int unreadable = 0;

    for (final CleanupScanTarget target in targets) {
      if (token.isCancelled) break;
      void targetProgress(CleanupScanProgress progress) {
        onProgress?.call(
          CleanupScanProgress(
            currentPath: '${target.label} · ${progress.currentPath}',
            visitedEntries: visitedOffset + progress.visitedEntries,
            candidateCount: candidates.length + progress.candidateCount,
            candidateBytes: bytesOffset + progress.candidateBytes,
          ),
        );
      }

      final CleanupScanResult result = switch (target.strategy) {
        CleanupTargetStrategy.directoryContents =>
          await scanDirectoryWithProgress(
            target.path,
            target.category,
            maxDepth: target.maxDepth,
            maxEntries: target.maxEntries,
            cancellationToken: token,
            sourceLabel: target.label,
            onProgress: targetProgress,
            minimumAgeHours: target.minimumAgeHours,
            minimumSizeBytes: target.minimumSizeBytes,
            includePatterns: target.includePatterns,
            excludePatterns: target.excludePatterns,
            riskLevel: target.riskLevel,
            impactNote: target.safetyNote,
          ),
        CleanupTargetStrategy.staleChildDirectories =>
          await _scanStaleChildDirectories(
            target,
            cancellationToken: token,
            onProgress: targetProgress,
          ),
        CleanupTargetStrategy.downloadSuggestions =>
          await _scanDownloadSuggestions(
            target,
            cancellationToken: token,
            onProgress: targetProgress,
          ),
        CleanupTargetStrategy.staleVsCodeExtensions =>
          await _scanStaleVsCodeExtensions(
            target,
            cancellationToken: token,
            onProgress: targetProgress,
          ),
        CleanupTargetStrategy.recycleBin => _scanRecycleBin(target),
      };
      for (final CleanupCandidate candidate in result.candidates) {
        candidates[_pathKey(candidate.path)] = candidate;
      }
      unreadable += result.unreadablePaths;
      visitedOffset += result.visitedEntries;
      bytesOffset = candidates.values.fold<int>(
        0,
        (int total, CleanupCandidate candidate) => total + candidate.size,
      );
    }
    return CleanupScanResult(
      candidates: candidates.values.toList(growable: false),
      cancelled: token.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visitedOffset,
      candidateBytes: bytesOffset,
    );
  }

  /// 把已过期的直属子目录聚合成单个候选。
  ///
  /// 智能体任务和构建发行包通常包含成千上万个小文件。逐文件列出不仅难以
  /// 审核，删除时也非常慢；按会话/版本目录聚合后，用户能看懂边界，清理器
  /// 也只需处理少量目录。扫描仍不跟随链接或目录联接点。
  static Future<CleanupScanResult> _scanStaleChildDirectories(
    CleanupScanTarget target, {
    required CleanupCancellationToken cancellationToken,
    void Function(CleanupScanProgress progress)? onProgress,
  }) async {
    final Directory root = Directory(target.path);
    if (!root.existsSync()) {
      return const CleanupScanResult(
        candidates: <CleanupCandidate>[],
        cancelled: false,
        unreadablePaths: 0,
      );
    }
    final DateTime cutoff = DateTime.now().subtract(
      Duration(hours: target.minimumAgeHours),
    );
    final List<CleanupCandidate> candidates = <CleanupCandidate>[];
    int visited = 0;
    int unreadable = 0;
    int bytes = 0;

    Future<int> measure(Directory directory) async {
      int total = 0;
      try {
        await for (final FileSystemEntity entity in directory.list(
          followLinks: false,
        )) {
          if (cancellationToken.isCancelled || visited >= target.maxEntries) {
            break;
          }
          visited++;
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file) {
            total += await File(entity.path).length();
          } else if (type == FileSystemEntityType.directory) {
            total += await measure(Directory(entity.path));
          }
          if (visited % 32 == 0) {
            onProgress?.call(
              CleanupScanProgress(
                currentPath: entity.path,
                visitedEntries: visited,
                candidateCount: candidates.length,
                candidateBytes: bytes + total,
              ),
            );
            await Future<void>.delayed(Duration.zero);
          }
        }
      } on FileSystemException {
        unreadable++;
      }
      return total;
    }

    try {
      await for (final FileSystemEntity entity in root.list(
        followLinks: false,
      )) {
        if (cancellationToken.isCancelled || visited >= target.maxEntries) {
          break;
        }
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final String name = _baseName(entity.path).toLowerCase();
        if (target.includePatterns.isNotEmpty &&
            !target.includePatterns.any(
              (String pattern) => _wildcardMatches(name, pattern),
            )) {
          continue;
        }
        if (target.excludePatterns.any(
          (String pattern) => _wildcardMatches(name, pattern),
        )) {
          continue;
        }
        final DateTime modified = Directory(entity.path).statSync().modified;
        if (target.minimumAgeHours > 0 && modified.isAfter(cutoff)) continue;
        final int size = await measure(Directory(entity.path));
        if (size < target.minimumSizeBytes) continue;
        bytes += size;
        candidates.add(
          CleanupCandidate(
            path: entity.path,
            size: size,
            category: target.category,
            reason: target.label,
            modified: modified,
            identity: CleanupFileIdentity.read(entity.path),
            sourceLabel: target.label,
            riskLevel: target.riskLevel,
            impactNote: target.safetyNote,
          ),
        );
        onProgress?.call(
          CleanupScanProgress(
            currentPath: entity.path,
            visitedEntries: visited,
            candidateCount: candidates.length,
            candidateBytes: bytes,
          ),
        );
      }
    } on FileSystemException {
      unreadable++;
    }
    return CleanupScanResult(
      candidates: candidates,
      cancelled: cancellationToken.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visited,
      candidateBytes: bytes,
    );
  }

  static CleanupScanResult _scanRecycleBin(CleanupScanTarget target) {
    final RecycleBinSnapshot? snapshot = RecycleBinService.query(target.path);
    if (snapshot == null) {
      return const CleanupScanResult(
        candidates: <CleanupCandidate>[],
        cancelled: false,
        unreadablePaths: 0,
      );
    }
    return CleanupScanResult(
      candidates: <CleanupCandidate>[
        CleanupCandidate(
          path: target.path,
          size: snapshot.bytes,
          category: CleanupCategory.recycleBin,
          reason: snapshot.items == 0
              ? '清理完成后统一清空回收站'
              : '${snapshot.items} 个现有回收站项目；清理完成后统一清空',
          sourceLabel: target.label,
          riskLevel: CleanupRiskLevel.systemManaged,
          impactNote: target.safetyNote,
        ),
      ],
      cancelled: false,
      unreadablePaths: 0,
      visitedEntries: snapshot.items + 1,
      candidateBytes: snapshot.bytes,
    );
  }

  static bool _wildcardMatches(String value, String wildcard) {
    final StringBuffer pattern = StringBuffer('^');
    for (final int rune in wildcard.toLowerCase().runes) {
      final String character = String.fromCharCode(rune);
      if (character == '*') {
        pattern.write('.*');
      } else if (character == '?') {
        pattern.write('.');
      } else {
        pattern.write(RegExp.escape(character));
      }
    }
    pattern.write(r'$');
    return RegExp(pattern.toString()).hasMatch(value);
  }

  static Future<CleanupScanResult> _scanDownloadSuggestions(
    CleanupScanTarget target, {
    required CleanupCancellationToken cancellationToken,
    void Function(CleanupScanProgress progress)? onProgress,
  }) async {
    final List<CleanupCandidate> candidates = <CleanupCandidate>[];
    int visited = 0;
    int unreadable = 0;
    int bytes = 0;
    final DateTime now = DateTime.now();
    final Set<String> partialExtensions = <String>{
      '.part',
      '.partial',
      '.crdownload',
      '.download',
      '.tmp',
    };
    final Set<String> packageExtensions = <String>{
      '.exe',
      '.msi',
      '.msix',
      '.appx',
      '.dmg',
      '.pkg',
      '.deb',
      '.rpm',
      '.apk',
      '.nupkg',
      '.vsix',
      '.whl',
      '.zip',
      '.7z',
      '.rar',
      '.iso',
      '.tar',
      '.tgz',
      '.gz',
      '.bz2',
      '.xz',
      '.zst',
    };

    Future<void> walk(Directory directory, int depth) async {
      if (cancellationToken.isCancelled || depth > 2) return;
      try {
        await for (final FileSystemEntity entity in directory.list(
          followLinks: false,
        )) {
          if (cancellationToken.isCancelled || visited >= _maxEntries) return;
          visited++;
          if (visited % 8 == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.directory) {
            await walk(Directory(entity.path), depth + 1);
            continue;
          }
          if (type != FileSystemEntityType.file) continue;
          final File file = File(entity.path);
          final DateTime modified = await file.lastModified();
          final String extension = _extension(entity.path);
          final Duration age = now.difference(modified);
          final bool incomplete =
              partialExtensions.contains(extension) && age.inHours >= 1;
          final bool oldPackage =
              packageExtensions.contains(extension) && age.inDays >= 30;
          if (!incomplete && !oldPackage) continue;
          final int size = await file.length();
          bytes += size;
          candidates.add(
            CleanupCandidate(
              path: entity.path,
              size: size,
              category: CleanupCategory.downloads,
              reason: incomplete ? '未完成的下载文件' : '超过 30 天的安装包/压缩包',
              modified: modified,
              identity: CleanupFileIdentity.read(entity.path),
              sourceLabel: target.label,
              riskLevel: target.riskLevel,
              impactNote: target.safetyNote,
            ),
          );
          onProgress?.call(
            CleanupScanProgress(
              currentPath: entity.path,
              visitedEntries: visited,
              candidateCount: candidates.length,
              candidateBytes: bytes,
            ),
          );
        }
      } on FileSystemException {
        unreadable++;
      }
    }

    await walk(Directory(target.path), 0);
    return CleanupScanResult(
      candidates: candidates,
      cancelled: cancellationToken.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visited,
      candidateBytes: bytes,
    );
  }

  static Future<CleanupScanResult> _scanStaleVsCodeExtensions(
    CleanupScanTarget target, {
    required CleanupCancellationToken cancellationToken,
    void Function(CleanupScanProgress progress)? onProgress,
  }) async {
    final Directory root = Directory(target.path);
    final Map<String, List<_ExtensionDirectory>> grouped =
        <String, List<_ExtensionDirectory>>{};
    int unreadable = 0;
    try {
      for (final FileSystemEntity entity in root.listSync(followLinks: false)) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final String name = _baseName(entity.path);
        final RegExpMatch? match = RegExp(r'^(.+)-(\d+\.\d+\.\d+)(?:[-+].*)?$')
            .firstMatch(name);
        if (match == null) continue;
        grouped
            .putIfAbsent(
              match.group(1)!.toLowerCase(),
              () => <_ExtensionDirectory>[],
            )
            .add(
              _ExtensionDirectory(
                path: entity.path,
                name: match.group(1)!,
                version: match.group(2)!,
              ),
            );
      }
    } on FileSystemException {
      unreadable++;
    }

    final List<CleanupCandidate> candidates = <CleanupCandidate>[];
    int visited = 0;
    int bytes = 0;
    for (final List<_ExtensionDirectory> versions in grouped.values) {
      if (cancellationToken.isCancelled || versions.length < 2) continue;
      versions.sort(
        (_ExtensionDirectory left, _ExtensionDirectory right) =>
            _compareVersions(right.version, left.version),
      );
      for (final _ExtensionDirectory stale in versions.skip(1)) {
        final CleanupScanResult result = await scanDirectoryWithProgress(
          stale.path,
          CleanupCategory.pluginResidual,
          cancellationToken: cancellationToken,
          sourceLabel: '旧版插件 ${stale.name} ${stale.version}',
          riskLevel: target.riskLevel,
          impactNote: target.safetyNote,
          onProgress: (CleanupScanProgress progress) {
            onProgress?.call(
              CleanupScanProgress(
                currentPath: progress.currentPath,
                visitedEntries: visited + progress.visitedEntries,
                candidateCount: candidates.length + progress.candidateCount,
                candidateBytes: bytes + progress.candidateBytes,
              ),
            );
          },
        );
        candidates.addAll(result.candidates);
        visited += result.visitedEntries;
        bytes += result.candidateBytes;
        unreadable += result.unreadablePaths;
      }
    }
    return CleanupScanResult(
      candidates: candidates,
      cancelled: cancellationToken.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visited,
      candidateBytes: bytes,
    );
  }

  static int _compareVersions(String left, String right) {
    final List<int> a = left.split('.').map(int.parse).toList();
    final List<int> b = right.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final int comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static String _extension(String path) {
    final String name = _baseName(path).toLowerCase();
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

  static String _baseName(String path) => path
      .replaceAll('/', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .where((String part) => part.isNotEmpty)
      .last;

  static String _pathKey(String path) =>
      path.replaceAll('/', Platform.pathSeparator).toLowerCase();
}

class _ExtensionDirectory {
  const _ExtensionDirectory({
    required this.path,
    required this.name,
    required this.version,
  });

  final String path;
  final String name;
  final String version;
}
