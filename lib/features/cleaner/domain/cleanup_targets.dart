import 'dart:io';

import 'cleanup_scanner.dart';
import 'cleanup_whitelist.dart';
import 'macos_cleanup_rule_catalog.dart';
import 'windows_cleanup_rule_catalog.dart';

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
    this.safetyNote = '',
    this.minimumAgeHours = 0,
    this.maxDepth = 8,
    this.minimumSizeBytes = 0,
    this.includePatterns = const <String>[],
    this.excludePatterns = const <String>[],
    this.ruleCatalogVersion,
  });

  final String id;
  final String label;
  final String path;
  final CleanupCategory category;
  final bool defaultEnabled;
  final CleanupTargetStrategy strategy;
  final String safetyNote;
  final int minimumAgeHours;
  final int maxDepth;
  final int minimumSizeBytes;
  final List<String> includePatterns;
  final List<String> excludePatterns;
  final int? ruleCatalogVersion;

  bool get highRisk => category.highRisk;
}

abstract final class CleanupTargetDiscovery {
  static const int catalogVersion = 6;

  static List<CleanupScanTarget> discover({
    Map<String, String>? environment,
    int? windowsBuild,
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    final List<CleanupScanTarget> targets = <CleanupScanTarget>[];
    final String? temp = env['TEMP'];
    final String? windows = env['WINDIR'];
    final String? local = env['LOCALAPPDATA'];
    final String? roaming = env['APPDATA'];
    final String? userProfile = env['USERPROFILE'];
    final String? home = env['HOME'];

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
            ('cursor', 'Cursor', 'Cursor'),
            ('windsurf', 'Windsurf', 'Windsurf'),
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
          safetyNote: '仅插件安装包和索引缓存；不会删除已安装插件',
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
        safetyNote: '可由 Gradle 重新生成；首次构建会变慢',
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
          safetyNote: '包管理器可重新下载；默认不勾选具体文件',
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
        safetyNote: '只有同一插件存在更高版本时才列出旧版本，且默认不勾选',
      );
      for (final (String id, String label, String folder)
          in <(String, String, String)>[
            ('cursor-stale-extensions', 'Cursor 旧版本插件', '.cursor'),
            ('windsurf-stale-extensions', 'Windsurf 旧版本插件', '.windsurf'),
          ]) {
        _addExisting(
          targets,
          id: id,
          label: label,
          path: _join(userProfile, <String>[folder, 'extensions']),
          category: CleanupCategory.pluginResidual,
          defaultEnabled: true,
          strategy: CleanupTargetStrategy.staleVsCodeExtensions,
          safetyNote: '只有同一插件存在更高版本时才列出旧版本，且默认不勾选',
        );
      }
      _addExisting(
        targets,
        id: 'downloads-suggestions',
        label: '下载目录清理建议',
        path: _join(userProfile, <String>['Downloads']),
        category: CleanupCategory.downloads,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.downloadSuggestions,
        safetyNote: '只建议未完成下载、旧安装包和旧压缩包；永不默认勾选',
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
      _addVisualStudioCaches(targets, local);
      _addJetBrainsCaches(targets, local);
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
        label: 'pnpm Store 下载缓存',
        path: _join(local, <String>['pnpm', 'store']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
        safetyNote: '仅扫描 store；不会触碰 pnpm 可执行文件和配置',
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

    if (home != null && home.trim().isNotEmpty) {
      _addMacTargets(targets, home, _currentMacosMajor(environment != null));
    }
    _addWindowsCatalogTargets(
      targets,
      env,
      windowsBuild ?? _currentWindowsBuild(environment != null),
    );

    final Map<String, CleanupScanTarget> unique = <String, CleanupScanTarget>{};
    for (final CleanupScanTarget target in targets) {
      final String? normalized = CleanupWhitelist.normalize(target.path);
      if (normalized != null) {
        final String pathKey = normalized.toLowerCase();
        final String key = target.ruleCatalogVersion == null
            ? pathKey
            : '$pathKey|${target.id}';
        unique[key] = target;
      }
    }
    return unique.values.toList(growable: false);
  }

  static void _addWindowsCatalogTargets(
    List<CleanupScanTarget> targets,
    Map<String, String> environment,
    int windowsBuild,
  ) {
    for (final WindowsCleanupRule rule in WindowsCleanupRuleCatalog.rules) {
      if (!rule.supportsBuild(windowsBuild)) continue;
      final String? path = _expandEnvironmentPath(
        rule.pathTemplate,
        environment,
      );
      if (path == null) continue;
      _addExisting(
        targets,
        id: rule.id,
        label: rule.label,
        path: path,
        category: switch (rule.category) {
          WindowsCleanupRuleCategory.systemCache => CleanupCategory.systemCache,
          WindowsCleanupRuleCategory.logs => CleanupCategory.logs,
          WindowsCleanupRuleCategory.applicationCache =>
            CleanupCategory.applicationCache,
          WindowsCleanupRuleCategory.developerCache => CleanupCategory.devCache,
        },
        defaultEnabled: rule.defaultEnabled,
        safetyNote: rule.note,
        minimumAgeHours: rule.minimumAgeHours,
        maxDepth: rule.maxDepth,
        minimumSizeBytes: rule.minimumSizeBytes,
        includePatterns: rule.includePatterns,
        excludePatterns: rule.excludePatterns,
        ruleCatalogVersion: WindowsCleanupRuleCatalog.version,
      );
    }
  }

  static String? _expandEnvironmentPath(
    String template,
    Map<String, String> environment,
  ) {
    final Map<String, String> normalized = <String, String>{
      for (final MapEntry<String, String> entry in environment.entries)
        entry.key.toUpperCase(): entry.value,
    };
    bool missing = false;
    final String expanded = template.replaceAllMapped(RegExp(r'%([^%]+)%'), (
      Match match,
    ) {
      final String? value = normalized[match.group(1)!.toUpperCase()];
      if (value == null || value.trim().isEmpty) {
        missing = true;
        return match.group(0)!;
      }
      return value.trim();
    });
    if (missing) return null;
    return expanded
        .replaceAll('\\', Platform.pathSeparator)
        .replaceAll('/', Platform.pathSeparator);
  }

  static int _currentWindowsBuild(bool injectedEnvironment) {
    if (injectedEnvironment && !Platform.isWindows) return 99999;
    final Iterable<int> versions = RegExp(r'\d{4,6}')
        .allMatches(Platform.operatingSystemVersion)
        .map((Match match) => int.parse(match.group(0)!));
    return versions.isEmpty
        ? 99999
        : versions.reduce((int left, int right) => left > right ? left : right);
  }

  static int _currentMacosMajor(bool injectedEnvironment) {
    if (injectedEnvironment && !Platform.isMacOS) return 99;
    final Match? match = RegExp(r'Version\s+(\d+)')
        .firstMatch(Platform.operatingSystemVersion);
    return match == null ? 99 : int.parse(match.group(1)!);
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
            lower.startsWith('cmake') ||
            lower.startsWith('ninja') ||
            lower.startsWith('node-gyp') ||
            lower.startsWith('pytest-') ||
            lower.startsWith('pip-') ||
            lower.startsWith('rustc') ||
            lower.startsWith('go-build') ||
            lower.startsWith('tmp') && lower.contains('debug') ||
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
    String safetyNote = '',
    int minimumAgeHours = 0,
    int maxDepth = 8,
    int minimumSizeBytes = 0,
    List<String> includePatterns = const <String>[],
    List<String> excludePatterns = const <String>[],
    int? ruleCatalogVersion,
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
        safetyNote: safetyNote,
        minimumAgeHours: minimumAgeHours,
        maxDepth: maxDepth,
        minimumSizeBytes: minimumSizeBytes,
        includePatterns: includePatterns,
        excludePatterns: excludePatterns,
        ruleCatalogVersion: ruleCatalogVersion,
      ),
    );
  }

  static void _addVisualStudioCaches(
    List<CleanupScanTarget> targets,
    String local,
  ) {
    final Directory root = Directory(
      _join(local, <String>['Microsoft', 'VisualStudio']),
    );
    if (!root.existsSync()) return;
    try {
      for (final FileSystemEntity product in root.listSync(
        followLinks: false,
      )) {
        if (FileSystemEntity.typeSync(product.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final String name = _baseName(product.path);
        for (final String cache in <String>[
          'ComponentModelCache',
          'ImageLibrary',
        ]) {
          _addExisting(
            targets,
            id: 'visual-studio-${name.toLowerCase()}-${cache.toLowerCase()}',
            label: 'Visual Studio $name $cache',
            path: _join(product.path, <String>[cache]),
            category: CleanupCategory.devCache,
            defaultEnabled: true,
            safetyNote: 'IDE 可重新生成；不会删除扩展、解决方案或源码',
          );
        }
      }
    } on FileSystemException {
      return;
    }
  }

  static void _addJetBrainsCaches(
    List<CleanupScanTarget> targets,
    String local,
  ) {
    for (final (String vendor, String label) in <(String, String)>[
      ('JetBrains', 'JetBrains'),
      ('Google', 'Android Studio'),
    ]) {
      final Directory root = Directory(_join(local, <String>[vendor]));
      if (!root.existsSync()) continue;
      try {
        for (final FileSystemEntity product in root.listSync(
          followLinks: false,
        )) {
          if (FileSystemEntity.typeSync(product.path, followLinks: false) !=
              FileSystemEntityType.directory) {
            continue;
          }
          final String name = _baseName(product.path);
          final String lower = name.toLowerCase();
          final bool recognized = vendor == 'JetBrains'
              ? RegExp(
                  r'^(idea|intellijidea|pycharm|webstorm|phpstorm|clion|rider|rubymine|goland|datagrip|androidstudio)',
                ).hasMatch(lower)
              : lower.startsWith('androidstudio');
          if (!recognized) continue;
          for (final String cache in <String>[
            'caches',
            'index',
            'tmp',
            'log',
          ]) {
            _addExisting(
              targets,
              id: '${vendor.toLowerCase()}-$lower-$cache',
              label: '$label $name $cache',
              path: _join(product.path, <String>[cache]),
              category: cache == 'log'
                  ? CleanupCategory.logs
                  : CleanupCategory.devCache,
              defaultEnabled: true,
              safetyNote: cache == 'log'
                  ? '仅诊断日志'
                  : 'IDE 可重新生成；不会删除插件、设置、项目或源码',
            );
          }
        }
      } on FileSystemException {
        continue;
      }
    }
  }

  static void _addMacTargets(
    List<CleanupScanTarget> targets,
    String home,
    int macosMajor,
  ) {
    for (final MacosCleanupRule rule in MacosCleanupRuleCatalog.rules) {
      if (!rule.supportsMajor(macosMajor)) continue;
      _addExisting(
        targets,
        id: rule.id,
        label: rule.label,
        path: _join(home, rule.relativePath),
        category: switch (rule.category) {
          MacosCleanupRuleCategory.browserCache => CleanupCategory.browserCache,
          MacosCleanupRuleCategory.applicationCache =>
            CleanupCategory.applicationCache,
          MacosCleanupRuleCategory.developerCache => CleanupCategory.devCache,
          MacosCleanupRuleCategory.logs => CleanupCategory.logs,
        },
        defaultEnabled: rule.defaultEnabled,
        safetyNote: rule.note,
        minimumAgeHours: rule.minimumAgeHours,
        maxDepth: rule.maxDepth,
        includePatterns: rule.includePatterns,
        excludePatterns: rule.excludePatterns,
        ruleCatalogVersion: MacosCleanupRuleCatalog.version,
      );
    }
    _addExisting(
      targets,
      id: 'mac-downloads-suggestions',
      label: '下载目录清理建议',
      path: _join(home, <String>['Downloads']),
      category: CleanupCategory.downloads,
      defaultEnabled: true,
      strategy: CleanupTargetStrategy.downloadSuggestions,
      safetyNote: '只建议未完成下载、旧安装包和旧压缩包；永不默认勾选',
    );
  }

  static String _baseName(String path) => path
      .replaceAll('/', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .where((String part) => part.isNotEmpty)
      .last;
}
