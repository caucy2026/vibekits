import 'dart:io';
import 'dart:isolate';

class HarnessDebugAreaUsage {
  const HarnessDebugAreaUsage({
    required this.name,
    required this.path,
    required this.totalBytes,
    required this.reclaimableBytes,
    required this.fileCount,
  });

  final String name;
  final String path;
  final int totalBytes;
  final int reclaimableBytes;
  final int fileCount;
}

class HarnessDebugStorageSummary {
  const HarnessDebugStorageSummary({
    required this.rootPath,
    required this.totalBytes,
    required this.reclaimableBytes,
    required this.fileCount,
    required this.unreadablePaths,
    required this.areas,
  });

  factory HarnessDebugStorageSummary.empty(String rootPath) =>
      HarnessDebugStorageSummary(
        rootPath: rootPath,
        totalBytes: 0,
        reclaimableBytes: 0,
        fileCount: 0,
        unreadablePaths: 0,
        areas: const <HarnessDebugAreaUsage>[],
      );

  final String rootPath;
  final int totalBytes;
  final int reclaimableBytes;
  final int fileCount;
  final int unreadablePaths;
  final List<HarnessDebugAreaUsage> areas;
}

/// Read-only accounting for Harness diagnostic artifacts.
///
/// It runs outside the UI isolate and never deletes content. Only artifacts
/// older than [minimumAge] are reported as reclaimable.
abstract final class HarnessDebugStorageService {
  static Future<HarnessDebugStorageSummary> inspect(
    String rootPath, {
    Duration minimumAge = const Duration(hours: 24),
  }) {
    final String root = rootPath.trim();
    if (root.isEmpty) {
      return Future<HarnessDebugStorageSummary>.value(
        HarnessDebugStorageSummary.empty(root),
      );
    }
    return Isolate.run<HarnessDebugStorageSummary>(
      () => _inspectHarnessDebugStorage(root, minimumAge.inMilliseconds),
    );
  }
}

HarnessDebugStorageSummary _inspectHarnessDebugStorage(
  String rootPath,
  int minimumAgeMilliseconds,
) {
  final Directory root = Directory(rootPath);
  if (!root.isAbsolute || !root.existsSync()) {
    return HarnessDebugStorageSummary.empty(rootPath);
  }
  final DateTime cutoff = DateTime.now().subtract(
    Duration(milliseconds: minimumAgeMilliseconds),
  );
  int totalBytes = 0;
  int reclaimableBytes = 0;
  int fileCount = 0;
  int unreadable = 0;
  final List<HarnessDebugAreaUsage> areas = <HarnessDebugAreaUsage>[];
  for (final String areaName in <String>['logs', 'screenshots', 'temp']) {
    final Directory area = Directory(
      '${root.path}${Platform.pathSeparator}$areaName',
    );
    int areaBytes = 0;
    int areaReclaimable = 0;
    int areaFiles = 0;
    if (area.existsSync()) {
      try {
        for (final FileSystemEntity entity in area.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          try {
            final FileStat stat = entity.statSync();
            areaBytes += stat.size;
            areaFiles++;
            if (stat.modified.isBefore(cutoff)) {
              areaReclaimable += stat.size;
            }
          } on FileSystemException {
            unreadable++;
          }
        }
      } on FileSystemException {
        unreadable++;
      }
    }
    totalBytes += areaBytes;
    reclaimableBytes += areaReclaimable;
    fileCount += areaFiles;
    areas.add(
      HarnessDebugAreaUsage(
        name: areaName,
        path: area.path,
        totalBytes: areaBytes,
        reclaimableBytes: areaReclaimable,
        fileCount: areaFiles,
      ),
    );
  }
  return HarnessDebugStorageSummary(
    rootPath: root.path,
    totalBytes: totalBytes,
    reclaimableBytes: reclaimableBytes,
    fileCount: fileCount,
    unreadablePaths: unreadable,
    areas: areas,
  );
}
