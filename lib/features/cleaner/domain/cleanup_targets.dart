import 'dart:io';

import 'cleanup_scanner.dart';
import 'cleanup_whitelist.dart';

class CleanupScanTarget {
  const CleanupScanTarget({
    required this.id,
    required this.label,
    required this.path,
    required this.category,
    required this.defaultEnabled,
  });

  final String id;
  final String label;
  final String path;
  final CleanupCategory category;
  final bool defaultEnabled;

  bool get highRisk => category.highRisk;
}

abstract final class CleanupTargetDiscovery {
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
    }
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      _addExisting(
        targets,
        id: 'gradle-cache',
        label: 'Gradle 构建缓存',
        path: _join(userProfile, <String>['.gradle', 'caches']),
        category: CleanupCategory.devCache,
        defaultEnabled: false,
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
        path: _join(local, <String>['npm-cache', '_cacache']),
        category: CleanupCategory.devCache,
        defaultEnabled: false,
      );
      _addExisting(
        targets,
        id: 'pip-cache',
        label: 'Python pip 下载缓存',
        path: _join(local, <String>['pip', 'Cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: false,
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

  static void _addExisting(
    List<CleanupScanTarget> targets, {
    required String id,
    required String label,
    required String path,
    required CleanupCategory category,
    required bool defaultEnabled,
  }) {
    if (!Directory(path).existsSync()) return;
    targets.add(
      CleanupScanTarget(
        id: id,
        label: label,
        path: path,
        category: category,
        defaultEnabled: defaultEnabled,
      ),
    );
  }

  static String _baseName(String path) => path
      .replaceAll('/', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .where((String part) => part.isNotEmpty)
      .last;
}
