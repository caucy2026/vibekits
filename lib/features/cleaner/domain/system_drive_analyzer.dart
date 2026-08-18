import 'dart:io';

import '../../archive/domain/disk_space.dart';
import 'cleanup_task.dart';

enum SystemDriveEntryKind {
  windowsSystem('Windows 系统', true),
  installedPrograms('已安装程序', true),
  userData('用户数据', true),
  recovery('恢复与启动', true),
  systemManaged('系统管理文件', true),
  logsAndCaches('日志与缓存', false),
  unknown('未知目录/文件', false);

  const SystemDriveEntryKind(this.label, this.normallyExpected);

  final String label;
  final bool normallyExpected;
}

class SystemDriveUsageEntry {
  const SystemDriveUsageEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.kind,
    required this.reason,
    required this.isDirectory,
    required this.complete,
    this.modified,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final SystemDriveEntryKind kind;
  final String reason;
  final bool isDirectory;
  final bool complete;
  final DateTime? modified;

  bool get needsReview => !kind.normallyExpected;
}

class SystemDriveAnalysisProgress {
  const SystemDriveAnalysisProgress({
    required this.currentPath,
    required this.visitedEntries,
    required this.measuredBytes,
    required this.completedRootEntries,
    required this.totalRootEntries,
  });

  final String currentPath;
  final int visitedEntries;
  final int measuredBytes;
  final int completedRootEntries;
  final int totalRootEntries;
}

class SystemDriveAnalysis {
  const SystemDriveAnalysis({
    required this.rootPath,
    required this.entries,
    required this.cancelled,
    required this.unreadablePaths,
    required this.visitedEntries,
    required this.measuredBytes,
    required this.totalBytes,
    required this.freeBytes,
    required this.availableBytes,
  });

  final String rootPath;
  final List<SystemDriveUsageEntry> entries;
  final bool cancelled;
  final int unreadablePaths;
  final int visitedEntries;
  final int measuredBytes;
  final int totalBytes;
  final int freeBytes;
  final int availableBytes;

  int get usedBytes => totalBytes > freeBytes ? totalBytes - freeBytes : 0;

  int get unaccountedBytes =>
      usedBytes > measuredBytes ? usedBytes - measuredBytes : 0;
}

abstract final class SystemDriveAnalyzer {
  static const int maxEntriesPerRoot = 250000;

  static const Map<String, (SystemDriveEntryKind, String)>
  _knownRoots = <String, (SystemDriveEntryKind, String)>{
    'windows': (SystemDriveEntryKind.windowsSystem, 'Windows 系统、组件存储、更新与驱动文件'),
    'program files': (SystemDriveEntryKind.installedPrograms, '64 位应用安装目录'),
    'program files (x86)': (
      SystemDriveEntryKind.installedPrograms,
      '32 位应用安装目录',
    ),
    'programdata': (SystemDriveEntryKind.installedPrograms, '应用共享数据、安装缓存和服务数据'),
    'users': (SystemDriveEntryKind.userData, '用户配置、文档和应用数据'),
    'recovery': (SystemDriveEntryKind.recovery, 'Windows 恢复环境'),
    'boot': (SystemDriveEntryKind.recovery, 'Windows 启动文件'),
    'efi': (SystemDriveEntryKind.recovery, 'UEFI 启动文件'),
    'system volume information': (
      SystemDriveEntryKind.systemManaged,
      '还原点、卷影复制和索引；由系统管理',
    ),
    r'$recycle.bin': (
      SystemDriveEntryKind.systemManaged,
      'Windows 回收站；应通过系统回收站接口管理',
    ),
    'perflogs': (SystemDriveEntryKind.logsAndCaches, 'Windows 性能诊断日志'),
    'estlog': (SystemDriveEntryKind.logsAndCaches, 'EST 加密软件日志；异常增长时可复核旧文件'),
  };

  static const Map<String, String> _knownSystemFiles = <String, String>{
    'pagefile.sys': '系统分页文件，由 Windows 管理',
    'hiberfil.sys': '休眠/快速启动文件，由 Windows 管理',
    'swapfile.sys': '现代应用交换文件，由 Windows 管理',
    'dumpstack.log.tmp': 'Windows 转储栈系统文件',
    'bootmgr': 'Windows 启动管理器',
  };

  static Future<SystemDriveAnalysis> analyze(
    String rootPath, {
    CleanupCancellationToken? cancellationToken,
    void Function(SystemDriveAnalysisProgress progress)? onProgress,
  }) async {
    final CleanupCancellationToken token =
        cancellationToken ?? CleanupCancellationToken();
    final Directory root = Directory(rootPath);
    final DiskSpaceSnapshot? disk = DiskSpace.snapshot(rootPath);
    if (!root.existsSync()) {
      return SystemDriveAnalysis(
        rootPath: rootPath,
        entries: const <SystemDriveUsageEntry>[],
        cancelled: false,
        unreadablePaths: 1,
        visitedEntries: 0,
        measuredBytes: 0,
        totalBytes: disk?.totalBytes ?? 0,
        freeBytes: disk?.freeBytes ?? 0,
        availableBytes: disk?.availableBytes ?? 0,
      );
    }

    final List<FileSystemEntity> roots = <FileSystemEntity>[];
    int unreadable = 0;
    try {
      await for (final FileSystemEntity entity in root.list(
        followLinks: false,
      )) {
        roots.add(entity);
      }
    } on FileSystemException {
      unreadable++;
    }
    final List<SystemDriveUsageEntry> entries = <SystemDriveUsageEntry>[];
    int visited = 0;
    int measured = 0;
    String currentPath = rootPath;
    final Stopwatch progressClock = Stopwatch()..start();

    void report(int completed, {bool force = false}) {
      if (onProgress == null ||
          (!force && progressClock.elapsedMilliseconds < 150)) {
        return;
      }
      progressClock.reset();
      onProgress(
        SystemDriveAnalysisProgress(
          currentPath: currentPath,
          visitedEntries: visited,
          measuredBytes: measured,
          completedRootEntries: completed,
          totalRootEntries: roots.length,
        ),
      );
    }

    for (int rootIndex = 0; rootIndex < roots.length; rootIndex++) {
      if (token.isCancelled) break;
      final FileSystemEntity entity = roots[rootIndex];
      currentPath = entity.path;
      final String name = _baseName(entity.path);
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) continue;
      int size = 0;
      bool complete = true;
      DateTime? modified;
      try {
        final FileStat stat = entity.statSync();
        modified = stat.modified;
        if (type == FileSystemEntityType.file) {
          size = stat.size;
          visited++;
        } else if (type == FileSystemEntityType.directory) {
          final _DirectoryMeasurement result = await _measureDirectory(
            Directory(entity.path),
            token,
            onVisit: (String path, int fileBytes) {
              currentPath = path;
              visited++;
              measured += fileBytes;
              report(rootIndex);
            },
          );
          size = result.sizeBytes;
          complete = result.complete;
          unreadable += result.unreadablePaths;
        }
      } on FileSystemException {
        unreadable++;
        complete = false;
      }
      if (type == FileSystemEntityType.file) measured += size;
      final (SystemDriveEntryKind, String) classification = _classify(
        name,
        isDirectory: type == FileSystemEntityType.directory,
      );
      entries.add(
        SystemDriveUsageEntry(
          path: entity.path,
          name: name,
          sizeBytes: size,
          kind: classification.$1,
          reason: classification.$2,
          isDirectory: type == FileSystemEntityType.directory,
          complete: complete,
          modified: modified,
        ),
      );
      report(rootIndex + 1, force: true);
    }
    entries.sort(
      (SystemDriveUsageEntry left, SystemDriveUsageEntry right) =>
          right.sizeBytes.compareTo(left.sizeBytes),
    );
    return SystemDriveAnalysis(
      rootPath: rootPath,
      entries: entries,
      cancelled: token.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visited,
      measuredBytes: entries.fold<int>(
        0,
        (int total, SystemDriveUsageEntry entry) => total + entry.sizeBytes,
      ),
      totalBytes: disk?.totalBytes ?? 0,
      freeBytes: disk?.freeBytes ?? 0,
      availableBytes: disk?.availableBytes ?? 0,
    );
  }

  static Future<_DirectoryMeasurement> _measureDirectory(
    Directory directory,
    CleanupCancellationToken token, {
    required void Function(String path, int fileBytes) onVisit,
  }) async {
    int size = 0;
    int visited = 0;
    int unreadable = 0;
    bool complete = true;
    final List<Directory> pending = <Directory>[directory];
    while (pending.isNotEmpty && !token.isCancelled) {
      final Directory current = pending.removeLast();
      try {
        await for (final FileSystemEntity entity in current.list(
          followLinks: false,
        )) {
          if (token.isCancelled) break;
          if (visited >= maxEntriesPerRoot) {
            complete = false;
            pending.clear();
            break;
          }
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.link) continue;
          visited++;
          if (type == FileSystemEntityType.directory) {
            pending.add(Directory(entity.path));
            onVisit(entity.path, 0);
          } else if (type == FileSystemEntityType.file) {
            try {
              final int fileBytes = await File(entity.path).length();
              size += fileBytes;
              onVisit(entity.path, fileBytes);
            } on FileSystemException {
              unreadable++;
            }
          }
          if (visited % 64 == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
        }
      } on FileSystemException {
        unreadable++;
      }
    }
    if (token.isCancelled) complete = false;
    return _DirectoryMeasurement(
      sizeBytes: size,
      complete: complete,
      unreadablePaths: unreadable,
    );
  }

  static (SystemDriveEntryKind, String) _classify(
    String name, {
    required bool isDirectory,
  }) {
    final String lower = name.toLowerCase();
    if (isDirectory) {
      return _knownRoots[lower] ??
          (
            SystemDriveEntryKind.unknown,
            '不是 Windows 标准根目录；需核对所属软件、修改时间和内容后再处理',
          );
    }
    final String? systemReason = _knownSystemFiles[lower];
    if (systemReason != null) {
      return (SystemDriveEntryKind.systemManaged, systemReason);
    }
    if (lower.endsWith('.log') ||
        lower.endsWith('.etl') ||
        lower.endsWith('.dmp') ||
        lower.endsWith('.hprof')) {
      return (SystemDriveEntryKind.logsAndCaches, '根目录诊断文件；大于阈值且过期时可进入清理复核');
    }
    return (SystemDriveEntryKind.unknown, '未知根目录文件；不得自动删除');
  }

  static String _baseName(String path) => path
      .replaceAll('/', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .where((String part) => part.isNotEmpty)
      .last;
}

class _DirectoryMeasurement {
  const _DirectoryMeasurement({
    required this.sizeBytes,
    required this.complete,
    required this.unreadablePaths,
  });

  final int sizeBytes;
  final bool complete;
  final int unreadablePaths;
}
