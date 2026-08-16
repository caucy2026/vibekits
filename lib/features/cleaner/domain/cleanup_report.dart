import 'dart:convert';
import 'dart:io';

import 'cleanup_deleter.dart';

abstract final class CleanupReportWriter {
  static Future<File> write(
    CleanupDeleteResult result, {
    DateTime? startedAt,
    DateTime? finishedAt,
    Directory? directory,
  }) async {
    final DateTime start = startedAt ?? DateTime.now();
    final DateTime finish = finishedAt ?? DateTime.now();
    final Directory target = directory ?? _defaultDirectory();
    await target.create(recursive: true);
    final File file = File(
      '${target.path}${Platform.pathSeparator}cleanup_${finish.millisecondsSinceEpoch}.json',
    );
    final Map<String, Object> report = <String, Object>{
      'version': 1,
      'taskId': 'cleanup-${start.millisecondsSinceEpoch}',
      'startedAt': start.toUtc().toIso8601String(),
      'finishedAt': finish.toUtc().toIso8601String(),
      'cancelled': result.cancelled,
      'succeeded': result.succeeded,
      'skipped': result.skipped,
      'failed': result.failed,
      'releasedBytes': result.releasedBytes,
      // Deliberately omit paths and file contents from the persisted report.
      'items': <Map<String, Object>>[
        for (int index = 0; index < result.items.length; index++)
          <String, Object>{
            'item': index + 1,
            'category': result.items[index].candidate.category.name,
            'size': result.items[index].candidate.size,
            'status': result.items[index].status.name,
            'reason': result.items[index].reason,
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
