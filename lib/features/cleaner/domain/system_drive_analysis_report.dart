import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'system_drive_analyzer.dart';
import 'system_drive_insights.dart';
import 'installed_application_service.dart';
import 'software_storage_analyzer.dart';

class SystemDriveAnalysisSnapshot {
  const SystemDriveAnalysisSnapshot({
    required this.generatedAt,
    required this.analyses,
    required this.installedApplications,
  });

  final DateTime generatedAt;
  final List<SystemDriveAnalysis> analyses;
  final List<InstalledApplication> installedApplications;
}

/// Stores the last completed disk analysis so reopening Cleaner never starts a
/// costly scan implicitly. A new snapshot is written only after an explicit
/// analysis action completes (or keeps completed volumes after cancellation).
abstract final class SystemDriveAnalysisSnapshotStore {
  static const String fileName = 'latest_drive_analysis.json';

  static Future<File> save(
    Iterable<SystemDriveAnalysis> analyses,
    List<InstalledApplication> installedApplications, {
    DateTime? generatedAt,
    Directory? directory,
  }) {
    final DateTime timestamp = generatedAt ?? DateTime.now();
    final String targetPath =
        (directory ?? SystemDriveAnalysisReportWriter.defaultDirectory()).path;
    final List<SystemDriveAnalysis> analysisList = analyses.toList(
      growable: false,
    );
    final List<InstalledApplication> applicationList =
        List<InstalledApplication>.of(installedApplications, growable: false);
    return Isolate.run<File>(
      () => _saveSync(analysisList, applicationList, timestamp, targetPath),
      debugName: 'vibekits-drive-analysis-save',
    );
  }

  static File _saveSync(
    List<SystemDriveAnalysis> analyses,
    List<InstalledApplication> installedApplications,
    DateTime timestamp,
    String targetPath,
  ) {
    final Directory target = Directory(targetPath)..createSync(recursive: true);
    final File file = File('${target.path}${Platform.pathSeparator}$fileName');
    final File temporary = File('${file.path}.tmp');
    final Map<String, Object?> payload = <String, Object?>{
      'version': 1,
      'generatedAt': timestamp.toUtc().toIso8601String(),
      'analyses': analyses.map(_analysisJson).toList(growable: false),
      'installedApplications': installedApplications
          .map(
            (InstalledApplication app) => <String, Object?>{
              'id': app.id,
              'name': app.name,
              'publisher': app.publisher,
              'version': app.version,
              'installLocation': app.installLocation,
              'estimatedSizeBytes': app.estimatedSizeBytes,
              'uninstallCommand': app.uninstallCommand,
            },
          )
          .toList(growable: false),
    };
    temporary.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (file.existsSync()) file.deleteSync();
    temporary.renameSync(file.path);
    return file;
  }

  static Future<SystemDriveAnalysisSnapshot?> load({Directory? directory}) {
    final String targetPath =
        (directory ?? SystemDriveAnalysisReportWriter.defaultDirectory()).path;
    return Isolate.run<SystemDriveAnalysisSnapshot?>(
      () => _loadSync(targetPath),
      debugName: 'vibekits-drive-analysis-load',
    );
  }

  static SystemDriveAnalysisSnapshot? _loadSync(String targetPath) {
    final File file = File('$targetPath${Platform.pathSeparator}$fileName');
    if (!file.existsSync()) return null;
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
        return null;
      }
      final DateTime? generatedAt = DateTime.tryParse(
        decoded['generatedAt']?.toString() ?? '',
      );
      final List<SystemDriveAnalysis> analyses = <SystemDriveAnalysis>[];
      for (final Object? value
          in decoded['analyses'] as List<Object?>? ?? const <Object?>[]) {
        if (value is Map<String, Object?>) {
          analyses.add(_analysisFromJson(value));
        }
      }
      final List<InstalledApplication> applications = <InstalledApplication>[];
      for (final Object? value
          in decoded['installedApplications'] as List<Object?>? ??
              const <Object?>[]) {
        if (value is! Map<String, Object?>) continue;
        applications.add(
          InstalledApplication(
            id: value['id']?.toString() ?? '',
            name: value['name']?.toString() ?? '',
            publisher: value['publisher']?.toString() ?? '',
            version: value['version']?.toString() ?? '',
            installLocation: value['installLocation']?.toString() ?? '',
            estimatedSizeBytes: _int(value['estimatedSizeBytes']),
            uninstallCommand: value['uninstallCommand']?.toString() ?? '',
          ),
        );
      }
      if (analyses.isEmpty || generatedAt == null) return null;
      return SystemDriveAnalysisSnapshot(
        generatedAt: generatedAt.toLocal(),
        analyses: List<SystemDriveAnalysis>.unmodifiable(analyses),
        installedApplications: List<InstalledApplication>.unmodifiable(
          applications,
        ),
      );
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _analysisJson(SystemDriveAnalysis analysis) =>
      <String, Object?>{
        'rootPath': analysis.rootPath,
        'cancelled': analysis.cancelled,
        'unreadablePaths': analysis.unreadablePaths,
        'visitedEntries': analysis.visitedEntries,
        'measuredBytes': analysis.measuredBytes,
        'totalBytes': analysis.totalBytes,
        'freeBytes': analysis.freeBytes,
        'availableBytes': analysis.availableBytes,
        'entries': analysis.entries.map(_entryJson).toList(growable: false),
        'breakdownEntries': analysis.breakdownEntries
            .map(_entryJson)
            .toList(growable: false),
      };

  static Map<String, Object?> _entryJson(SystemDriveUsageEntry entry) =>
      <String, Object?>{
        'path': entry.path,
        'name': entry.name,
        'sizeBytes': entry.sizeBytes,
        'kind': entry.kind.name,
        'reason': entry.reason,
        'isDirectory': entry.isDirectory,
        'complete': entry.complete,
        'modified': entry.modified?.toUtc().toIso8601String(),
        'ownerLabel': entry.ownerLabel,
        'parentPath': entry.parentPath,
        'deletePolicy': entry.deletePolicy.name,
      };

  static SystemDriveAnalysis _analysisFromJson(Map<String, Object?> json) =>
      SystemDriveAnalysis(
        rootPath: json['rootPath']?.toString() ?? '',
        entries: _entries(json['entries']),
        breakdownEntries: _entries(json['breakdownEntries']),
        cancelled: json['cancelled'] == true,
        unreadablePaths: _int(json['unreadablePaths']),
        visitedEntries: _int(json['visitedEntries']),
        measuredBytes: _int(json['measuredBytes']),
        totalBytes: _int(json['totalBytes']),
        freeBytes: _int(json['freeBytes']),
        availableBytes: _int(json['availableBytes']),
      );

  static List<SystemDriveUsageEntry> _entries(Object? value) {
    final List<SystemDriveUsageEntry> entries = <SystemDriveUsageEntry>[];
    for (final Object? item in value as List<Object?>? ?? const <Object?>[]) {
      if (item is! Map<String, Object?>) continue;
      entries.add(
        SystemDriveUsageEntry(
          path: item['path']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          sizeBytes: _int(item['sizeBytes']),
          kind: _enumByName(
            SystemDriveEntryKind.values,
            item['kind']?.toString(),
            SystemDriveEntryKind.unknown,
          ),
          reason: item['reason']?.toString() ?? '',
          isDirectory: item['isDirectory'] == true,
          complete: item['complete'] == true,
          modified: DateTime.tryParse(item['modified']?.toString() ?? '')
              ?.toLocal(),
          ownerLabel: item['ownerLabel']?.toString() ?? '',
          parentPath: item['parentPath']?.toString() ?? '',
          deletePolicy: _enumByName(
            SystemDriveDeletePolicy.values,
            item['deletePolicy']?.toString(),
            SystemDriveDeletePolicy.protected,
          ),
        ),
      );
    }
    return List<SystemDriveUsageEntry>.unmodifiable(entries);
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) => values.where((T value) => value.name == name).firstOrNull ?? fallback;

  static int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
}

abstract final class SystemDriveAnalysisReportWriter {
  static Future<File> write(
    SystemDriveAnalysis analysis, {
    DateTime? generatedAt,
    Directory? directory,
    List<InstalledApplication> installedApplications =
        const <InstalledApplication>[],
  }) async {
    final DateTime timestamp = generatedAt ?? DateTime.now();
    final Directory target = directory ?? defaultDirectory();
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
    final SystemDriveInsights insights = SystemDriveInsights.from(analysis);
    final List<SoftwareStorageSummary> software =
        SoftwareStorageAnalyzer.summarize(analysis, installedApplications);
    final Map<String, Object?> report = <String, Object?>{
      'version': 4,
      'generatedAt': timestamp.toUtc().toIso8601String(),
      'rootPath': analysis.rootPath,
      'cancelled': analysis.cancelled,
      'disk': <String, int>{
        'totalBytes': analysis.totalBytes,
        'usedBytes': analysis.usedBytes,
        'freeBytes': analysis.freeBytes,
        'availableBytes': analysis.availableBytes,
        'logicalMeasuredBytes': analysis.logicalMeasuredBytes,
        'unaccountedBytes': analysis.unaccountedBytes,
        'logicalOvercountBytes': analysis.logicalOvercountBytes,
      },
      'measurement': <String, Object?>{
        'kind': 'logical-file-length',
        'notice': analysis.hasLogicalOvercount
            ? '目录逻辑量包含 NTFS 硬链接重复计数，不能当作物理占用相加。'
            : '目录逻辑量用于定位占用来源；与物理已用量的差值包括不可读路径、文件系统元数据和系统保留空间。',
      },
      'scan': <String, int>{
        'rootEntries': analysis.entries.length,
        'visitedEntries': analysis.visitedEntries,
        'unreadablePaths': analysis.unreadablePaths,
      },
      'totalsByKind': totalsByKind,
      'insights': <String, Object?>{
        'storagePressure': insights.storagePressure.name,
        'storagePressureLabel': insights.storagePressure.label,
        'storagePressureSummary': insights.storagePressureSummary,
        'systemBaseline': insights.systemBaseline,
        'priorities': insights.priorities
            .take(100)
            .map((SystemDriveEntryAssessment item) => item.toJson())
            .toList(growable: false),
        'softwareOwners': insights.softwareOwners
            .take(100)
            .map((SystemDriveEntryAssessment item) => item.toJson())
            .toList(growable: false),
      },
      'entries': <Map<String, Object?>>[
        for (final SystemDriveUsageEntry entry in analysis.entries)
          _entryJson(entry),
      ],
      'breakdownEntries': <Map<String, Object?>>[
        for (final SystemDriveUsageEntry entry in analysis.breakdownEntries)
          _entryJson(entry),
      ],
      'softwareStorage': <Map<String, Object?>>[
        for (final SoftwareStorageSummary item in software)
          <String, Object?>{
            'name': item.name,
            'publisher': item.application?.publisher ?? '',
            'version': item.application?.version ?? '',
            'installPaths': item.installPaths,
            'installBytes': item.installBytes,
            'dataBytes': item.dataBytes,
            'cacheBytes': item.cacheBytes,
            'totalBytes': item.totalBytes,
            'assessment': item.level.name,
            'assessmentLabel': item.level.label,
            'reason': item.assessment,
            'canCleanCache': item.canCleanCache,
            'canUninstall': item.canUninstall,
          },
      ],
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    return file;
  }

  static Map<String, Object?> _entryJson(SystemDriveUsageEntry entry) =>
      <String, Object?>{
        'path': entry.path,
        'name': entry.name,
        'sizeBytes': entry.sizeBytes,
        'kind': entry.kind.name,
        'kindLabel': entry.kind.label,
        'owner': entry.ownerLabel,
        'parentPath': entry.parentPath,
        'assessment': entry.needsReview ? 'review' : 'expected',
        'deletePolicy': entry.deletePolicy.name,
        'reason': entry.reason,
        'isDirectory': entry.isDirectory,
        'measurementComplete': entry.complete,
        'modifiedAt': entry.modified?.toUtc().toIso8601String(),
      };

  static Directory defaultDirectory() {
    final String base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    return Directory(
      '$base${Platform.pathSeparator}Vibekits${Platform.pathSeparator}Reports',
    );
  }
}
