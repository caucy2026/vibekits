import 'dart:io';

import 'cleanup_scanner.dart';
import 'cleanup_whitelist.dart';

enum CleanupTargetStrategy {
  directoryContents,
  downloadSuggestions,
  staleVsCodeExtensions,
}

class CleanupScanTarget {
  const CleanupScanTarget({
    required this.id,
    required this.label,
    required this.path,
    required this.category,
    required this.defaultEnabled,
    this.strategy = CleanupTargetStrategy.directoryContents,
  });

  final String id;
  final String label;
  final String path;
  final CleanupCategory category;
  final bool defaultEnabled;
  final CleanupTargetStrategy strategy;

  bool get highRisk => category.highRisk;
}

abstract final class CleanupTargetDiscovery {
  static const int catalogVersion = 3;

  static List<CleanupScanTarget> discover({Map<String, String>? environment}) {
    final Map<String, String> env = environment ?? Platform.environment;
    final List<CleanupScanTarget> targets = <CleanupScanTarget>[];
    final String? temp = env['TEMP'];
    final String? windows = env['WINDIR'];
    final String? local = env['LOCALAPPDATA'];
    final String? roaming = env['APPDATA'];
    final String? userProfile = env['USERPROFILE'];

    if (temp != null && temp.trim().isNotEmpty) {
      targets.add(
        CleanupScanTarget(
          id: 'user-temp',
          label: '用户临时文件',
          path: temp,
          category: CleanupCategory.userTemp,
          defaultEnabled: true,
        ),
      );
      _addDebugTempDirectories(targets, temp);
    }
    if (roaming != null && roaming.trim().isNotEmpty) {
      for (final (String id, String product, String folder)
          in <(String, String, String)>[
            ('vscode', 'Visual Studio Code', 'Code'),
            ('discord', 'Discord', 'discord'),
          ]) {
        for (final String cache in <String>[
          'Cache',
          'Code Cache',
          'GPUCache',
          'CachedData',
        ]) {
          _addExisting(
            targets,
            id: '$id-${cache.toLowerCase().replaceAll(' ', '-')}',
            label: '$product $cache',
            path: _join(roaming, <String>[folder, cache]),
            category: CleanupCategory.applicationCache,
            defaultEnabled: true,
          );
        }
      }
      for (final (String id, String label, String folder)
          in <(String, String, String)>[
            (
              'vscode-extension-download-cache',
              'VS Code 插件下载缓存',
              'CachedExtensionVSIXs',
            ),
            (
              'vscode-extension-metadata-cache',
              'VS Code 插件元数据缓存',
              'CachedExtensions',
            ),
          ]) {
        _addExisting(
          targets,
          id: id,
          label: label,
          path: _join(roaming, <String>['Code', folder]),
          category: CleanupCategory.pluginCache,
          defaultEnabled: true,
        );
      }
    }
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      _addExisting(
        targets,
        id: 'gradle-cache',
        label: 'Gradle 构建缓存',
        path: _join(userProfile, <String>['.gradle', 'caches']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
      );
      for (final (String id, String label, List<String> parts)
          in <(String, String, List<String>)>[
            ('nuget-cache', 'NuGet 下载与包缓存', <String>['.nuget', 'packages']),
            ('maven-cache', 'Maven 本地仓库缓存', <String>['.m2', 'repository']),
            (
              'cargo-registry-cache',
              'Rust Cargo 下载缓存',
              <String>['.cargo', 'registry', 'cache'],
            ),
            (
              'go-module-download-cache',
              'Go 模块下载缓存',
              <String>['go', 'pkg', 'mod', 'cache', 'download'],
            ),
            ('android-cache', 'Android 工具缓存', <String>['.android', 'cache']),
          ]) {
        _addExisting(
          targets,
          id: id,
          label: label,
          path: _join(userProfile, parts),
          category: CleanupCategory.devCache,
          defaultEnabled: true,
        );
      }
      _addExisting(
        targets,
        id: 'vscode-stale-extensions',
        label: 'VS Code 旧版本插件',
        path: _join(userProfile, <String>['.vscode', 'extensions']),
        category: CleanupCategory.pluginResidual,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.staleVsCodeExtensions,
      );
      _addExisting(
        targets,
        id: 'downloads-suggestions',
        label: '下载目录清理建议',
        path: _join(userProfile, <String>['Downloads']),
        category: CleanupCategory.downloads,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.downloadSuggestions,
      );
    }
    if (windows != null && windows.trim().isNotEmpty) {
      targets.add(
        CleanupScanTarget(
          id: 'windows-temp',
          label: 'Windows 临时目录',
          path: '$windows${Platform.pathSeparator}Temp',
          category: CleanupCategory.windowsTemp,
          defaultEnabled: false,
        ),
      );
    }
    if (local != null && local.trim().isNotEmpty) {
      _addExisting(
        targets,
        id: 'directx-shader-cache',
        label: 'DirectX 着色器缓存',
        path: _join(local, <String>['D3DSCache']),
        category: CleanupCategory.systemCache,
        defaultEnabled: true,
      );
      _addExisting(
        targets,
        id: 'windows-error-reports',
        label: 'Windows 错误报告',
        path: _join(local, <String>['Microsoft', 'Windows', 'WER']),
        category: CleanupCategory.logs,
        defaultEnabled: true,
      );
      _addExisting(
        targets,
        id: 'npm-cache',
        label: 'npm 下载缓存',
        path: _join(local, <String>['npm-cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
      );
      _addExisting(
        targets,
        id: 'pip-cache',
        label: 'Python pip 下载缓存',
        path: _join(local, <String>['pip', 'Cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
      );
      _addExisting(
        targets,
        id: 'pub-cache',
        label: 'Dart / Flutter Pub 下载缓存',
        path: _join(local, <String>['Pub', 'Cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
      );
      _addExisting(
        targets,
        id: 'yarn-cache',
        label: 'Yarn 下载缓存',
        path: _join(local, <String>['Yarn', 'Cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
      );
      _addExisting(
        targets,
        id: 'pnpm-cache',
        label: 'pnpm 下载缓存',
        path: _join(local, <String>['pnpm']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
      );
      _addChromiumProfiles(
        targets,
        product: 'Edge',
        idPrefix: 'edge',
        userData: _join(local, <String>['Microsoft', 'Edge', 'User Data']),
      );
      _addChromiumProfiles(
        targets,
        product: 'Chrome',
        idPrefix: 'chrome',
        userData: _join(local, <String>['Google', 'Chrome', 'User Data']),
      );
      _addFirefoxProfiles(targets, local);
      _addExisting(
        targets,
        id: 'crash-dumps',
        label: '用户崩溃转储',
        path: _join(local, <String>['CrashDumps']),
        category: CleanupCategory.logs,
        defaultEnabled: true,
      );
    }

    final Map<String, CleanupScanTarget> unique = <String, CleanupScanTarget>{};
    for (final CleanupScanTarget target in targets) {
      final String? normalized = CleanupWhitelist.normalize(target.path);
      if (normalized != null) unique[normalized.toLowerCase()] = target;
    }
    return unique.values.toList(growable: false);
  }

  static void _addChromiumProfiles(
    List<CleanupScanTarget> targets, {
    required String product,
    required String idPrefix,
    required String userData,
  }) {
    final Directory root = Directory(userData);
    if (!root.existsSync()) return;
    List<FileSystemEntity> profiles;
    try {
      profiles = root.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity profile in profiles) {
      if (FileSystemEntity.typeSync(profile.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      final String name = _baseName(profile.path);
      if (name != 'Default' && !name.startsWith('Profile ')) continue;
      for (final String cacheName in <String>[
        'Cache',
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        _nested(<String>['Service Worker', 'CacheStorage']),
      ]) {
        _addExisting(
          targets,
          id: '$idPrefix-${name.toLowerCase().replaceAll(' ', '-')}-${cacheName.toLowerCase().replaceAll(' ', '-')}',
          label:
              '$product $name ${cacheName.replaceAll(Platform.pathSeparator, ' / ')}',
          path: _join(profile.path, cacheName.split(Platform.pathSeparator)),
          category: CleanupCategory.browserCache,
          defaultEnabled: true,
        );
      }
    }
  }

  static void _addFirefoxProfiles(
    List<CleanupScanTarget> targets,
    String local,
  ) {
    final Directory profiles = Directory(
      _join(local, <String>['Mozilla', 'Firefox', 'Profiles']),
    );
    if (!profiles.existsSync()) return;
    try {
      for (final FileSystemEntity profile in profiles.listSync(
        followLinks: false,
      )) {
        if (FileSystemEntity.typeSync(profile.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final String name = _baseName(profile.path);
        _addExisting(
          targets,
          id: 'firefox-${name.toLowerCase()}',
          label: 'Firefox $name cache2',
          path: _join(profile.path, <String>['cache2']),
          category: CleanupCategory.browserCache,
          defaultEnabled: true,
        );
      }
    } on FileSystemException {
      return;
    }
  }

  static String _join(String root, List<String> parts) =>
      <String>[root, ...parts].join(Platform.pathSeparator);

  static String _nested(List<String> parts) =>
      parts.join(Platform.pathSeparator);

  static void _addDebugTempDirectories(
    List<CleanupScanTarget> targets,
    String temp,
  ) {
    final Directory root = Directory(temp);
    if (!root.existsSync()) return;
    final DateTime cutoff = DateTime.now().subtract(const Duration(hours: 24));
    try {
      for (final FileSystemEntity entity in root.listSync(followLinks: false)) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final String name = _baseName(entity.path);
        final String lower = name.toLowerCase();
        final bool knownDebugTemp =
            lower.startsWith('flutter_') ||
            lower.startsWith('dart_') ||
            lower.startsWith('pub_') ||
            lower.startsWith('gradle') ||
            lower.startsWith('vscode-') ||
            lower.startsWith('scoped_dir');
        if (!knownDebugTemp ||
            Directory(entity.path).statSync().modified.isAfter(cutoff)) {
          continue;
        }
        _addExisting(
          targets,
          id: 'debug-temp-${lower.hashCode.abs()}',
          label: '过期调试临时目录 $name',
          path: entity.path,
          category: CleanupCategory.debugArtifacts,
          defaultEnabled: true,
        );
      }
    } on FileSystemException {
      return;
    }
  }

  static void _addExisting(
    List<CleanupScanTarget> targets, {
    required String id,
    required String label,
    required String path,
    required CleanupCategory category,
    required bool defaultEnabled,
    CleanupTargetStrategy strategy = CleanupTargetStrategy.directoryContents,
  }) {
    if (!Directory(path).existsSync()) return;
    targets.add(
      CleanupScanTarget(
        id: id,
        label: label,
        path: path,
        category: category,
        defaultEnabled: defaultEnabled,
        strategy: strategy,
      ),
    );
  }

  static String _baseName(String path) => path
      .replaceAll('/', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .where((String part) => part.isNotEmpty)
      .last;
}
