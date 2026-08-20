import 'installed_application_service.dart';
import 'system_drive_analyzer.dart';
import 'system_drive_insights.dart';

class SoftwareStorageSummary {
  const SoftwareStorageSummary({
    required this.id,
    required this.name,
    required this.installBytes,
    required this.dataBytes,
    required this.cacheBytes,
    required this.level,
    required this.assessment,
    required this.installEntries,
    required this.dataEntries,
    required this.cacheEntries,
    this.application,
  });

  final String id;
  final String name;
  final int installBytes;
  final int dataBytes;
  final int cacheBytes;
  final SystemDriveAssessmentLevel level;
  final String assessment;
  final List<SystemDriveUsageEntry> installEntries;
  final List<SystemDriveUsageEntry> dataEntries;
  final List<SystemDriveUsageEntry> cacheEntries;
  final InstalledApplication? application;

  int get totalBytes => installBytes + dataBytes;
  bool get sizeKnown => totalBytes > 0;
  bool get canCleanCache =>
      application != null &&
      cacheEntries.any((SystemDriveUsageEntry entry) => entry.canDelete);
  bool get canUninstall => application?.canUninstall == true;

  /// Registry path first, measured installation roots as a reliable fallback.
  List<String> get installPaths {
    final Set<String> paths = <String>{};
    final String registered = application?.installLocation.trim() ?? '';
    if (registered.isNotEmpty) paths.add(registered);
    for (final SystemDriveUsageEntry entry in installEntries) {
      if (entry.path.trim().isNotEmpty) paths.add(entry.path.trim());
    }
    return List<String>.unmodifiable(paths);
  }
}

abstract final class SoftwareStorageAnalyzer {
  static const int _gib = 1024 * 1024 * 1024;

  static List<SoftwareStorageSummary> summarize(
    SystemDriveAnalysis analysis,
    List<InstalledApplication> installed,
  ) {
    final Map<String, _SoftwareBuilder> builders = <String, _SoftwareBuilder>{};
    final Map<String, InstalledApplication> applications =
        <String, InstalledApplication>{};
    for (final InstalledApplication app in installed) {
      final String key = InstalledApplicationService.normalizeOwner(app.name);
      if (key.isNotEmpty) applications[key] = app;
    }

    _SoftwareBuilder builderFor(String owner, {String path = ''}) {
      final String normalized = InstalledApplicationService.normalizeOwner(
        owner,
      );
      final String matchedKey = _bestApplicationKey(
        normalized,
        applications,
        path: path,
      );
      final String key = matchedKey.isEmpty ? normalized : matchedKey;
      return builders.putIfAbsent(
        key,
        () => _SoftwareBuilder(
          id: key,
          name: applications[key]?.name ?? owner,
          application: applications[key],
        ),
      );
    }

    for (final InstalledApplication app in applications.values) {
      builderFor(app.name);
    }
    for (final SystemDriveUsageEntry entry in analysis.breakdownEntries) {
      if (entry.ownerLabel.trim().isEmpty) continue;
      final _SoftwareBuilder builder = builderFor(
        entry.ownerLabel,
        path: entry.path,
      );
      switch (entry.kind) {
        case SystemDriveEntryKind.installedPrograms:
          builder.installEntries.add(entry);
        case SystemDriveEntryKind.softwareData:
          builder.dataEntries.add(entry);
        case SystemDriveEntryKind.logsAndCaches:
          builder.cacheEntries.add(entry);
        default:
          break;
      }
    }

    final List<SoftwareStorageSummary> summaries = <SoftwareStorageSummary>[];
    for (final _SoftwareBuilder builder in builders.values) {
      final int measuredInstall = _uniqueTotal(builder.installEntries);
      final int estimated = builder.application?.estimatedSizeBytes ?? 0;
      final int installBytes = measuredInstall > 0
          ? measuredInstall
          : estimated;
      final int cacheBytes = _uniqueTotal(builder.cacheEntries);
      final int measuredData = _uniqueTotal(builder.dataEntries);
      // Cache entries are descendants of the software-data owner directory.
      // Use the larger value so the same files are never counted twice.
      final int dataBytes = measuredData > cacheBytes
          ? measuredData
          : cacheBytes;
      if (installBytes == 0 && dataBytes == 0 && builder.application == null) {
        continue;
      }
      final (SystemDriveAssessmentLevel, String) assessment = _assess(
        installBytes: installBytes,
        dataBytes: dataBytes,
        cacheBytes: cacheBytes,
      );
      summaries.add(
        SoftwareStorageSummary(
          id: builder.id,
          name: builder.name,
          installBytes: installBytes,
          dataBytes: dataBytes,
          cacheBytes: cacheBytes,
          level: assessment.$1,
          assessment: assessment.$2,
          installEntries: List<SystemDriveUsageEntry>.unmodifiable(
            builder.installEntries,
          ),
          dataEntries: List<SystemDriveUsageEntry>.unmodifiable(
            builder.dataEntries,
          ),
          cacheEntries: List<SystemDriveUsageEntry>.unmodifiable(
            builder.cacheEntries,
          ),
          application: builder.application,
        ),
      );
    }
    summaries.sort((SoftwareStorageSummary left, SoftwareStorageSummary right) {
      final int severity = right.level.index.compareTo(left.level.index);
      if (severity != 0) return severity;
      return right.totalBytes.compareTo(left.totalBytes);
    });
    return List<SoftwareStorageSummary>.unmodifiable(summaries);
  }

  static int _uniqueTotal(List<SystemDriveUsageEntry> entries) {
    final Map<String, int> byPath = <String, int>{};
    for (final SystemDriveUsageEntry entry in entries) {
      byPath[entry.path.toLowerCase()] = entry.sizeBytes;
    }
    return byPath.values.fold<int>(0, (int total, int value) => total + value);
  }

  static String _bestApplicationKey(
    String owner,
    Map<String, InstalledApplication> applications, {
    String path = '',
  }) {
    if (applications.containsKey(owner)) return owner;
    final String normalizedPath = _normalizePath(path);
    if (normalizedPath.isNotEmpty) {
      String locationMatch = '';
      for (final MapEntry<String, InstalledApplication> item
          in applications.entries) {
        final String location = _normalizePath(item.value.installLocation);
        if (location.isNotEmpty &&
            (normalizedPath == location ||
                normalizedPath.startsWith('$location/')) &&
            location.length > locationMatch.length) {
          locationMatch = item.key;
        }
      }
      if (locationMatch.isNotEmpty) return locationMatch;
    }
    if (owner.length < 3) return '';
    if (_genericOwners.contains(owner)) return '';
    String best = '';
    for (final String key in applications.keys) {
      if (key.contains(owner) || owner.contains(key)) {
        if (key.length > best.length) best = key;
      }
    }
    return best;
  }

  static String _normalizePath(String path) => path
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp('/+'), '/')
      .replaceFirst(RegExp(r'/$'), '')
      .toLowerCase();

  static const Set<String> _genericOwners = <String>{
    'microsoft',
    'google',
    'adobe',
    'common files',
    'windowsapps',
    'packages',
  };

  static (SystemDriveAssessmentLevel, String) _assess({
    required int installBytes,
    required int dataBytes,
    required int cacheBytes,
  }) {
    if (installBytes == 0 && dataBytes == 0) {
      return (
        SystemDriveAssessmentLevel.normal,
        'Windows 未报告体积，扫描也未关联到安装目录，当前无法判断实际占用。',
      );
    }
    if (cacheBytes >= 5 * _gib) {
      return (
        SystemDriveAssessmentLevel.critical,
        '缓存/日志超过 5 GiB，明显异常，建议关闭软件后优先清理。',
      );
    }
    if (cacheBytes >= _gib) {
      return (SystemDriveAssessmentLevel.review, '缓存/日志超过 1 GiB，需要复核是否持续增长。');
    }
    if (dataBytes >= 10 * _gib) {
      return (
        SystemDriveAssessmentLevel.review,
        '软件数据超过 10 GiB；应区分项目、数据库、下载内容与可再生缓存。',
      );
    }
    if (installBytes >= 20 * _gib) {
      return (
        SystemDriveAssessmentLevel.attention,
        '安装体积超过 20 GiB；如果不再使用，应通过卸载器移除。',
      );
    }
    return (SystemDriveAssessmentLevel.normal, '未发现达到异常阈值的缓存或软件数据。');
  }
}

class _SoftwareBuilder {
  _SoftwareBuilder({
    required this.id,
    required this.name,
    required this.application,
  });

  final String id;
  final String name;
  final InstalledApplication? application;
  final List<SystemDriveUsageEntry> installEntries = <SystemDriveUsageEntry>[];
  final List<SystemDriveUsageEntry> dataEntries = <SystemDriveUsageEntry>[];
  final List<SystemDriveUsageEntry> cacheEntries = <SystemDriveUsageEntry>[];
}
