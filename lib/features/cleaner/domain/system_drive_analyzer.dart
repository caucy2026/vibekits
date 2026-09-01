import 'dart:io';

import '../../archive/domain/disk_space.dart';
import 'cleanup_task.dart';

enum SystemDriveEntryKind {
  windowsSystem('Windows 系统', true),
  installedPrograms('已安装程序', true),
  softwareData('软件数据', true),
  userData('用户数据', true),
  recovery('恢复与启动', true),
  systemManaged('系统管理文件', true),
  logsAndCaches('日志与缓存', false),
  unknown('未知目录/文件', false);

  const SystemDriveEntryKind(this.label, this.normallyExpected);

  final String label;
  final bool normallyExpected;
}

enum SystemDriveDeletePolicy {
  protected,
  recycleAfterConfirmation;

  bool get canDelete => this == recycleAfterConfirmation;
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
    this.ownerLabel = '',
    this.parentPath = '',
    this.deletePolicy = SystemDriveDeletePolicy.protected,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final SystemDriveEntryKind kind;
  final String reason;
  final bool isDirectory;
  final bool complete;
  final DateTime? modified;
  final String ownerLabel;
  final String parentPath;
  final SystemDriveDeletePolicy deletePolicy;

  bool get needsReview => !kind.normallyExpected;
  bool get canDelete => deletePolicy.canDelete;
  bool get isBreakdown => parentPath.isNotEmpty;
}

class SystemDriveAnalysisProgress {
  const SystemDriveAnalysisProgress({
    required this.currentPath,
    required this.visitedEntries,
    required this.measuredBytes,
    required this.completedRootEntries,
    required this.totalRootEntries,
    this.completedEntry,
    this.completedBreakdownEntries = const <SystemDriveUsageEntry>[],
  });

  final String currentPath;
  final int visitedEntries;
  final int measuredBytes;
  final int completedRootEntries;
  final int totalRootEntries;
  final SystemDriveUsageEntry? completedEntry;
  final List<SystemDriveUsageEntry> completedBreakdownEntries;
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
    this.breakdownEntries = const <SystemDriveUsageEntry>[],
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
  final List<SystemDriveUsageEntry> breakdownEntries;

  int get usedBytes => totalBytes > freeBytes ? totalBytes - freeBytes : 0;

  /// The sum of logical file lengths found below every root entry.
  ///
  /// On Windows this may be greater than [usedBytes] because component-store
  /// hard links can expose the same physical bytes from multiple directories.
  int get logicalMeasuredBytes => measuredBytes;

  int get unaccountedBytes =>
      usedBytes > measuredBytes ? usedBytes - measuredBytes : 0;

  int get logicalOvercountBytes =>
      measuredBytes > usedBytes ? measuredBytes - usedBytes : 0;

  bool get hasLogicalOvercount => logicalOvercountBytes > 0;
}

abstract final class SystemDriveAnalyzer {
  static const int maxEntriesPerRoot = 1000000;

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
    final bool systemVolume =
        _isSystemVolume(rootPath) ||
        roots.any(
          (FileSystemEntity entry) =>
              _baseName(entry.path).toLowerCase() == 'windows',
        );
    roots.sort(
      (FileSystemEntity left, FileSystemEntity right) => _rootPriority(
        left.path,
        systemVolume: systemVolume,
      ).compareTo(_rootPriority(right.path, systemVolume: systemVolume)),
    );
    final List<SystemDriveUsageEntry> entries = <SystemDriveUsageEntry>[];
    final List<SystemDriveUsageEntry> breakdownEntries =
        <SystemDriveUsageEntry>[];
    int visited = 0;
    int measured = 0;
    String currentPath = rootPath;
    final Stopwatch progressClock = Stopwatch()..start();

    void report(
      int completed, {
      bool force = false,
      SystemDriveUsageEntry? completedEntry,
      List<SystemDriveUsageEntry> completedBreakdownEntries =
          const <SystemDriveUsageEntry>[],
    }) {
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
          completedEntry: completedEntry,
          completedBreakdownEntries: completedBreakdownEntries,
        ),
      );
    }

    int nextRootIndex = 0;
    int completedRoots = 0;

    Future<void> worker() async {
      while (!token.isCancelled && nextRootIndex < roots.length) {
        final int rootIndex = nextRootIndex++;
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
        _DirectoryMeasurement? measurement;
        try {
          final FileStat stat = entity.statSync();
          modified = stat.modified;
          if (type == FileSystemEntityType.file) {
            size = stat.size;
            visited++;
            measured += size;
          } else if (type == FileSystemEntityType.directory) {
            measurement = await _measureDirectory(
              Directory(entity.path),
              token,
              onVisit: (String path, int fileBytes) {
                currentPath = path;
                visited++;
                measured += fileBytes;
                report(completedRoots);
              },
            );
            size = measurement.sizeBytes;
            complete = measurement.complete;
            unreadable += measurement.unreadablePaths;
          }
        } on FileSystemException {
          unreadable++;
          complete = false;
        }
        final (SystemDriveEntryKind, String) classification = _classify(
          name,
          isDirectory: type == FileSystemEntityType.directory,
          systemVolume: systemVolume,
        );
        final SystemDriveUsageEntry entry = SystemDriveUsageEntry(
          path: entity.path,
          name: name,
          sizeBytes: size,
          kind: classification.$1,
          reason: classification.$2,
          isDirectory: type == FileSystemEntityType.directory,
          complete: complete,
          modified: modified,
          ownerLabel: classification.$1.label,
          deletePolicy: _deletePolicyFor(classification.$1),
        );
        final List<SystemDriveUsageEntry> rootBreakdown = measurement == null
            ? const <SystemDriveUsageEntry>[]
            : _buildBreakdownEntries(
                entry,
                measurement.breakdownBytes,
                measurement.cacheBreakdownBytes,
              );
        entries.add(entry);
        breakdownEntries.addAll(rootBreakdown);
        completedRoots++;
        report(
          completedRoots,
          force: true,
          completedEntry: entry,
          completedBreakdownEntries: rootBreakdown,
        );
      }
    }

    final int workerCount = roots.length < 3 ? roots.length : 3;
    // Publish a cancellable starting state before fast local filesystems can
    // finish their first root. Yield once so a UI cancellation message sent
    // from another isolate is observed before traversal continues.
    report(0, force: true);
    await Future<void>.delayed(Duration.zero);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    entries.sort(
      (SystemDriveUsageEntry left, SystemDriveUsageEntry right) =>
          right.sizeBytes.compareTo(left.sizeBytes),
    );
    breakdownEntries.sort(
      (SystemDriveUsageEntry left, SystemDriveUsageEntry right) =>
          right.sizeBytes.compareTo(left.sizeBytes),
    );
    final int logicalMeasuredBytes = entries.fold<int>(
      0,
      (int total, SystemDriveUsageEntry entry) => total + entry.sizeBytes,
    );
    return SystemDriveAnalysis(
      rootPath: rootPath,
      entries: entries,
      cancelled: token.isCancelled,
      unreadablePaths: unreadable,
      visitedEntries: visited,
      measuredBytes: logicalMeasuredBytes,
      // Some sandboxed/temp roots do not expose a volume statistic. Preserve
      // a useful non-zero capacity floor from the bytes we actually measured
      // instead of returning an internally contradictory zero total.
      totalBytes: disk?.totalBytes ?? logicalMeasuredBytes,
      freeBytes: disk?.freeBytes ?? 0,
      availableBytes: disk?.availableBytes ?? 0,
      breakdownEntries: breakdownEntries,
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
    final Map<String, int> breakdownBytes = <String, int>{};
    final Map<String, int> cacheBreakdownBytes = <String, int>{};
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
              final String? bucket = _breakdownBucket(
                directory.path,
                entity.path,
              );
              if (bucket != null) {
                breakdownBytes.update(
                  bucket,
                  (int value) => value + fileBytes,
                  ifAbsent: () => fileBytes,
                );
              }
              final String? cacheBucket = _cacheBreakdownBucket(
                directory.path,
                entity.path,
              );
              if (cacheBucket != null) {
                cacheBreakdownBytes.update(
                  cacheBucket,
                  (int value) => value + fileBytes,
                  ifAbsent: () => fileBytes,
                );
              }
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
      breakdownBytes: breakdownBytes,
      cacheBreakdownBytes: cacheBreakdownBytes,
    );
  }

  static int _rootPriority(String path, {required bool systemVolume}) {
    final String name = _baseName(path).toLowerCase();
    final (SystemDriveEntryKind, String) classification = _classify(
      name,
      isDirectory:
          FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.directory,
      systemVolume: systemVolume,
    );
    return switch (classification.$1) {
      SystemDriveEntryKind.logsAndCaches => 0,
      SystemDriveEntryKind.unknown => 1,
      SystemDriveEntryKind.installedPrograms ||
      SystemDriveEntryKind.softwareData => 2,
      SystemDriveEntryKind.userData => 3,
      SystemDriveEntryKind.windowsSystem => 4,
      _ => 5,
    };
  }

  static SystemDriveDeletePolicy _deletePolicyFor(SystemDriveEntryKind kind) =>
      switch (kind) {
        SystemDriveEntryKind.logsAndCaches =>
          SystemDriveDeletePolicy.recycleAfterConfirmation,
        _ => SystemDriveDeletePolicy.protected,
      };

  static String? _breakdownBucket(String rootPath, String filePath) {
    final String normalizedRoot = rootPath.replaceAll('\\', '/');
    final String normalizedFile = filePath.replaceAll('\\', '/');
    if (!normalizedFile.toLowerCase().startsWith(
      '${normalizedRoot.toLowerCase()}/',
    )) {
      return null;
    }
    final List<String> parts = normalizedFile
        .substring(normalizedRoot.length + 1)
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;
    final String rootName = _baseName(rootPath).toLowerCase();
    if (rootName != 'users' && parts.length < 2) return null;
    int componentCount = 1;
    if (rootName == 'users') {
      componentCount = parts.length >= 3 ? 2 : 1;
      if (parts.length >= 5 &&
          parts[1].toLowerCase() == 'appdata' &&
          <String>{
            'local',
            'locallow',
            'roaming',
          }.contains(parts[2].toLowerCase())) {
        componentCount = 4;
        // Microsoft/Google/Tencent are vendors, not useful software names.
        // Attribute their data to the next product component (Edge, Chrome,
        // WXWork...) so the UI reports real per-application usage.
        if (parts.length >= 5 &&
            _genericVendorNames.contains(parts[3].toLowerCase())) {
          componentCount = 5;
        }
      }
    } else if (parts.length >= 2 &&
        (_genericVendorNames.contains(parts.first.toLowerCase()) ||
            parts.first.toLowerCase() == 'windowsapps')) {
      componentCount = 2;
    }
    if (parts.length < componentCount) componentCount = parts.length;
    return '$rootPath${Platform.pathSeparator}'
        '${parts.take(componentCount).join(Platform.pathSeparator)}';
  }

  static List<SystemDriveUsageEntry> _buildBreakdownEntries(
    SystemDriveUsageEntry parent,
    Map<String, int> breakdownBytes,
    Map<String, int> cacheBreakdownBytes,
  ) {
    final String rootName = parent.name.toLowerCase();
    return <SystemDriveUsageEntry>[
      for (final MapEntry<String, int> item in breakdownBytes.entries)
        if (item.value > 0)
          _breakdownEntry(parent, item.key, item.value, rootName),
      for (final MapEntry<String, int> item in cacheBreakdownBytes.entries)
        if (item.value > 0)
          _cacheBreakdownEntry(parent, item.key, item.value, rootName),
    ];
  }

  static SystemDriveUsageEntry _cacheBreakdownEntry(
    SystemDriveUsageEntry parent,
    String path,
    int sizeBytes,
    String rootName,
  ) {
    final String relative = path
        .substring(parent.path.length)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp('^/+'), '');
    final String owner = _softwareOwnerFor(parent.path, path);
    final bool safeUserCache =
        rootName == 'programdata' ||
        rootName == 'users' ||
        parent.kind == SystemDriveEntryKind.userData;
    return SystemDriveUsageEntry(
      path: path,
      name: relative.replaceAll('/', ' / '),
      sizeBytes: sizeBytes,
      kind: SystemDriveEntryKind.logsAndCaches,
      reason: '$owner 产生的可再生缓存或日志；清理前应关闭对应软件',
      isDirectory: true,
      complete: parent.complete,
      ownerLabel: owner,
      parentPath: parent.path,
      deletePolicy: safeUserCache
          ? SystemDriveDeletePolicy.recycleAfterConfirmation
          : SystemDriveDeletePolicy.protected,
    );
  }

  static SystemDriveUsageEntry _breakdownEntry(
    SystemDriveUsageEntry parent,
    String path,
    int sizeBytes,
    String rootName,
  ) {
    final String relative = path
        .substring(parent.path.length)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp('^/+'), '');
    final List<String> parts = relative.split('/');
    final String leaf = parts.last;
    SystemDriveEntryKind kind;
    String reason;
    if (rootName == 'windows') {
      kind = _looksLikeCachePath(path)
          ? SystemDriveEntryKind.logsAndCaches
          : SystemDriveEntryKind.windowsSystem;
      reason = kind == SystemDriveEntryKind.logsAndCaches
          ? 'Windows 生成的临时文件或日志目录'
          : 'Windows 组件：$leaf';
    } else if (rootName == 'program files' ||
        rootName == 'program files (x86)') {
      kind = _looksLikeCachePath(path)
          ? SystemDriveEntryKind.logsAndCaches
          : SystemDriveEntryKind.installedPrograms;
      reason = kind == SystemDriveEntryKind.logsAndCaches
          ? '$leaf 软件产生的缓存或日志'
          : '$leaf 的程序安装文件；应优先通过卸载管理';
    } else if (rootName == 'programdata') {
      kind = _looksLikeCachePath(path)
          ? SystemDriveEntryKind.logsAndCaches
          : SystemDriveEntryKind.softwareData;
      reason = kind == SystemDriveEntryKind.logsAndCaches
          ? '$leaf 软件产生的共享缓存或日志'
          : '$leaf 的共享配置、服务数据或安装缓存';
    } else if (rootName == 'users' &&
        parts.length >= 4 &&
        parts[1].toLowerCase() == 'appdata') {
      kind = _looksLikeCachePath(path)
          ? SystemDriveEntryKind.logsAndCaches
          : SystemDriveEntryKind.softwareData;
      reason = kind == SystemDriveEntryKind.logsAndCaches
          ? '$leaf 软件产生的用户缓存或日志'
          : '$leaf 的用户配置和应用数据';
    } else {
      kind = SystemDriveEntryKind.userData;
      reason = '用户 ${parts.first} 的 $leaf 数据';
    }
    return SystemDriveUsageEntry(
      path: path,
      name: relative.replaceAll('/', ' / '),
      sizeBytes: sizeBytes,
      kind: kind,
      reason: reason,
      isDirectory: true,
      complete: parent.complete,
      ownerLabel: leaf,
      parentPath: parent.path,
      deletePolicy:
          kind == SystemDriveEntryKind.logsAndCaches &&
              (rootName == 'programdata' || rootName == 'users')
          ? SystemDriveDeletePolicy.recycleAfterConfirmation
          : SystemDriveDeletePolicy.protected,
    );
  }

  static bool _looksLikeCachePath(String path) {
    final String leaf = _baseName(path).toLowerCase();
    return leaf == 'cache' ||
        leaf == 'caches' ||
        leaf == 'temp' ||
        leaf == 'tmp' ||
        leaf == 'log' ||
        leaf == 'logs' ||
        leaf == 'crashdumps' ||
        leaf == 'crash reports';
  }

  static const Set<String> _genericVendorNames = <String>{
    'microsoft',
    'google',
    'tencent',
    'adobe',
    'apple',
    'oracle',
  };

  static String? _cacheBreakdownBucket(String rootPath, String filePath) {
    final String? softwareRoot = _breakdownBucket(rootPath, filePath);
    if (softwareRoot == null) return null;
    final String normalizedSoftware = softwareRoot.replaceAll('\\', '/');
    final String normalizedFile = filePath.replaceAll('\\', '/');
    if (!normalizedFile.toLowerCase().startsWith(
      '${normalizedSoftware.toLowerCase()}/',
    )) {
      return null;
    }
    final List<String> descendants = normalizedFile
        .substring(normalizedSoftware.length + 1)
        .split('/');
    for (int index = 0; index < descendants.length - 1; index++) {
      final String lower = descendants[index].toLowerCase();
      if (_cacheDirectoryNames.contains(lower)) {
        return '$softwareRoot${Platform.pathSeparator}'
            '${descendants.take(index + 1).join(Platform.pathSeparator)}';
      }
    }
    return null;
  }

  static String _softwareOwnerFor(String rootPath, String path) {
    final String normalizedRoot = rootPath.replaceAll('\\', '/');
    final String normalizedPath = path.replaceAll('\\', '/');
    final List<String> parts = normalizedPath
        .substring(normalizedRoot.length + 1)
        .split('/');
    if (_baseName(rootPath).toLowerCase() == 'users' && parts.length >= 4) {
      return parts[3];
    }
    return parts.isEmpty ? _baseName(path) : parts.first;
  }

  static const Set<String> _cacheDirectoryNames = <String>{
    'cache',
    'caches',
    'cache2',
    'code cache',
    'gpucache',
    'dawncache',
    'shadercache',
    'temp',
    'tmp',
    'log',
    'logs',
    'crashdumps',
    'crash reports',
    'cachestorage',
  };

  static (SystemDriveEntryKind, String) _classify(
    String name, {
    required bool isDirectory,
    required bool systemVolume,
  }) {
    final String lower = name.toLowerCase();
    if (isDirectory) {
      if (_cacheDirectoryNames.contains(lower)) {
        return (
          SystemDriveEntryKind.logsAndCaches,
          '明确命名的缓存或日志目录；确认无软件正在写入后可清理',
        );
      }
      final (SystemDriveEntryKind, String)? known = _knownRoots[lower];
      if (known != null) return known;
      if (!systemVolume) {
        return (
          SystemDriveEntryKind.userData,
          '非系统盘普通数据；仅列出占用，不会直接删除项目、媒体或用户文件',
        );
      }
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

  static bool _isSystemVolume(String rootPath) {
    final String normalized = rootPath.replaceAll('/', '\\').toLowerCase();
    final String? systemDrive = Platform.environment['SystemDrive'];
    if (systemDrive != null && systemDrive.trim().isNotEmpty) {
      final String expected = systemDrive.endsWith('\\')
          ? systemDrive
          : '$systemDrive\\';
      return normalized == expected.toLowerCase();
    }
    final String? windows = Platform.environment['WINDIR'];
    return windows != null &&
        windows.length >= 3 &&
        normalized == windows.substring(0, 3).toLowerCase();
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
    required this.breakdownBytes,
    required this.cacheBreakdownBytes,
  });

  final int sizeBytes;
  final bool complete;
  final int unreadablePaths;
  final Map<String, int> breakdownBytes;
  final Map<String, int> cacheBreakdownBytes;
}
