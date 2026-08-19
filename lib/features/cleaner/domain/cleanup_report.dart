import 'dart:convert';
import 'dart:io';

import 'cleanup_deleter.dart';

abstract final class CleanupReportWriter {
  static const int currentVersion = 2;

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
      'version': currentVersion,
      'taskId': 'cleanup-${start.millisecondsSinceEpoch}',
      'startedAt': start.toUtc().toIso8601String(),
      'finishedAt': finish.toUtc().toIso8601String(),
      'cancelled': result.cancelled,
      'succeeded': result.succeeded,
      'skipped': result.skipped,
      'failed': result.failed,
      'releasedBytes': result.releasedBytes,
      'items': <Map<String, Object>>[
        for (int index = 0; index < result.items.length; index++)
          <String, Object>{
            'item': index + 1,
            'path': result.items[index].candidate.path,
            'category': result.items[index].candidate.category.name,
            'source': result.items[index].candidate.sourceLabel ?? '',
            'size': result.items[index].candidate.size,
            if (result.items[index].candidate.modified != null)
              'modifiedAt': result.items[index].candidate.modified!
                  .toUtc()
                  .toIso8601String(),
            'status': result.items[index].status.name,
            'reason': result.items[index].reason,
          },
      ],
    };
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await temporary.rename(file.path);
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

  static Future<List<CleanupReportEntry>> list({
    Directory? directory,
    int limit = 50,
  }) async {
    final Directory target = directory ?? _defaultDirectory();
    if (!await target.exists()) return const <CleanupReportEntry>[];
    final List<File> files = await target
        .list(followLinks: false)
        .where((FileSystemEntity entity) => entity is File)
        .cast<File>()
        .where(
          (File file) =>
              file.uri.pathSegments.last.startsWith('cleanup_') &&
              file.path.toLowerCase().endsWith('.json'),
        )
        .toList();
    files.sort(
      (File left, File right) =>
          right.lastModifiedSync().compareTo(left.lastModifiedSync()),
    );
    final List<CleanupReportEntry> reports = <CleanupReportEntry>[];
    for (final File file in files.take(limit)) {
      try {
        final Map<String, Object?> json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        reports.add(CleanupReportEntry.fromJson(file, json));
      } on Object {
        reports.add(
          CleanupReportEntry(
            file: file,
            finishedAt: await file.lastModified(),
            succeeded: 0,
            skipped: 0,
            failed: 1,
            releasedBytes: 0,
            cancelled: false,
            items: const <Map<String, Object?>>[],
            unreadable: true,
          ),
        );
      }
    }
    return reports;
  }

  static Future<bool> delete(File file, {Directory? directory}) async {
    final Directory root = directory ?? _defaultDirectory();
    final String rootPath = root.absolute.path.toLowerCase();
    final String filePath = file.absolute.path.toLowerCase();
    if (!filePath.startsWith('$rootPath${Platform.pathSeparator}') ||
        !filePath.endsWith('.json')) {
      return false;
    }
    try {
      if (await file.exists()) await file.delete();
      return !await file.exists();
    } on FileSystemException {
      return false;
    }
  }
}

class CleanupReportEntry {
  const CleanupReportEntry({
    required this.file,
    required this.finishedAt,
    required this.succeeded,
    required this.skipped,
    required this.failed,
    required this.releasedBytes,
    required this.cancelled,
    required this.items,
    this.unreadable = false,
  });

  factory CleanupReportEntry.fromJson(File file, Map<String, Object?> json) {
    int integer(String key) => json[key] is int ? json[key]! as int : 0;
    return CleanupReportEntry(
      file: file,
      finishedAt:
          DateTime.tryParse(json['finishedAt'] as String? ?? '') ??
          file.lastModifiedSync(),
      succeeded: integer('succeeded'),
      skipped: integer('skipped'),
      failed: integer('failed'),
      releasedBytes: integer('releasedBytes'),
      cancelled: json['cancelled'] == true,
      items: json['items'] is List<Object?>
          ? (json['items']! as List<Object?>)
                .whereType<Map<String, Object?>>()
                .toList(growable: false)
          : const <Map<String, Object?>>[],
    );
  }

  final File file;
  final DateTime finishedAt;
  final int succeeded;
  final int skipped;
  final int failed;
  final int releasedBytes;
  final bool cancelled;
  final List<Map<String, Object?>> items;
  final bool unreadable;
}
