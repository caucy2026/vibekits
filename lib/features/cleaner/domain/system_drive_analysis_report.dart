import 'dart:convert';
import 'dart:io';

import 'system_drive_analyzer.dart';

abstract final class SystemDriveAnalysisReportWriter {
  static Future<File> write(
    SystemDriveAnalysis analysis, {
    DateTime? generatedAt,
    Directory? directory,
  }) async {
    final DateTime timestamp = generatedAt ?? DateTime.now();
    final Directory target = directory ?? _defaultDirectory();
    await target.create(recursive: true);
    final File file = File(
      '${target.path}${Platform.pathSeparator}'
      'system_drive_${timestamp.millisecondsSinceEpoch}.json',
    );
    final Map<String, int> totalsByKind = <String, int>{};
    for (final SystemDriveUsageEntry entry in analysis.entries) {
      totalsByKind.update(
        entry.kind.name,
        (int value) => value + entry.sizeBytes,
        ifAbsent: () => entry.sizeBytes,
      );
    }
    final Map<String, Object?> report = <String, Object?>{
      'version': 1,
      'generatedAt': timestamp.toUtc().toIso8601String(),
      'rootPath': analysis.rootPath,
      'cancelled': analysis.cancelled,
      'disk': <String, int>{
        'totalBytes': analysis.totalBytes,
        'usedBytes': analysis.usedBytes,
        'freeBytes': analysis.freeBytes,
        'availableBytes': analysis.availableBytes,
        'measuredBytes': analysis.measuredBytes,
        'unaccountedBytes': analysis.unaccountedBytes,
      },
      'scan': <String, int>{
        'rootEntries': analysis.entries.length,
        'visitedEntries': analysis.visitedEntries,
        'unreadablePaths': analysis.unreadablePaths,
      },
      'totalsByKind': totalsByKind,
      'entries': <Map<String, Object?>>[
        for (final SystemDriveUsageEntry entry in analysis.entries)
          <String, Object?>{
            'path': entry.path,
            'name': entry.name,
            'sizeBytes': entry.sizeBytes,
            'kind': entry.kind.name,
            'kindLabel': entry.kind.label,
            'assessment': entry.needsReview ? 'review' : 'expected',
            'reason': entry.reason,
            'isDirectory': entry.isDirectory,
            'measurementComplete': entry.complete,
            'modifiedAt': entry.modified?.toUtc().toIso8601String(),
          },
      ],
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    return file;
  }

  static Directory _defaultDirectory() {
    final String base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    return Directory(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Reports',
    );
  }
}
