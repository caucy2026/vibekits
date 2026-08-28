import 'dart:io';

import 'cleanup_scanner.dart';
import 'cleanup_platform_policy.dart';
import 'cleanup_whitelist.dart';
import 'macos_cleanup_rule_catalog.dart';
import 'windows_cleanup_rule_catalog.dart';

enum CleanupTargetStrategy {
  directoryContents,
  staleChildDirectories,
  downloadSuggestions,
  staleVsCodeExtensions,
  recycleBin,
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
    this.maxEntries = 5000,
    this.minimumSizeBytes = 0,
    this.includePatterns = const <String>[],
    this.excludePatterns = const <String>[],
    this.ruleCatalogVersion,
    this.riskLevel = CleanupRiskLevel.safe,
    this.ruleSource = '内置规则',
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
  final int maxEntries;
  final int minimumSizeBytes;
  final List<String> includePatterns;
  final List<String> excludePatterns;
  final int? ruleCatalogVersion;
  final CleanupRiskLevel riskLevel;
  final String ruleSource;

  bool get highRisk => category.highRisk || riskLevel.highRisk;
}

abstract final class CleanupTargetDiscovery {
  static const int catalogVersion = 17;

  static List<CleanupScanTarget> discover({
    Map<String, String>? environment,
    int? windowsBuild,
    String appCacheDirectory = '',
    String harnessDebugDirectory = '',
    CleanupPlatform? platform,
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    final CleanupPlatform targetPlatform = platform ?? CleanupPlatform.current;
    final List<CleanupScanTarget> targets = <CleanupScanTarget>[];
    if (targetPlatform == CleanupPlatform.macos) {
      final String? home = env['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        _addMacTargets(targets, home, _currentMacosMajor(environment != null));
      }
      _addHarnessDebugTargets(targets, harnessDebugDirectory);
      return _deduplicate(targets);
    }
    if (targetPlatform == CleanupPlatform.android) {
      _addAndroidTargets(
        targets,
        env,
        appCacheDirectory: appCacheDirectory,
        harnessDebugDirectory: harnessDebugDirectory,
      );
      return _deduplicate(targets);
    }
    if (targetPlatform != CleanupPlatform.windows) {
      return const <CleanupScanTarget>[];
    }
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
      _addExisting(
        targets,
        id: '360-browser-old-kernel-residuals',
        label: '360 浏览器旧内核残留',
        path: _join(roaming, <String>['secoresdk', '360se6', 'Application']),
        category: CleanupCategory.pluginResidual,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.staleChildDirectories,
        minimumAgeHours: 24 * 7,
        maxEntries: 100000,
        includePatterns: const <String>['*.old'],
        riskLevel: CleanupRiskLevel.cautious,
        safetyNote: '只列出名称明确以 .old 结尾的旧内核目录；当前版本和用户数据不会删除',
      );
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
        id: 'antigravity-stale-task-artifacts',
        label: 'Antigravity / Gemini 旧任务调试产物',
        path: _join(userProfile, <String>['.gemini', 'antigravity', 'brain']),
        category: CleanupCategory.debugArtifacts,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.staleChildDirectories,
        minimumAgeHours: 24 * 14,
        maxEntries: 100000,
        riskLevel: CleanupRiskLevel.cautious,
        safetyNote: '按旧任务会话整包列出，包含截图、日志和任务上下文；删除后无法查看对应旧任务的调试证据',
      );
      _addExisting(
        targets,
        id: 'antigravity-stale-conversations',
        label: 'Antigravity / Gemini 旧会话数据库',
        path: _join(userProfile, <String>[
          '.gemini',
          'antigravity',
          'conversations',
        ]),
        category: CleanupCategory.debugArtifacts,
        defaultEnabled: true,
        minimumAgeHours: 24 * 14,
        maxEntries: 1000,
        includePatterns: const <String>['*.db'],
        riskLevel: CleanupRiskLevel.cautious,
        safetyNote: '旧智能体会话正文；删除后旧会话不能恢复，默认不勾选',
      );
      _addExisting(
        targets,
        id: 'gradle-stale-distributions',
        label: 'Gradle 过期发行包',
        path: _join(userProfile, <String>['.gradle', 'wrapper', 'dists']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.staleChildDirectories,
        minimumAgeHours: 24 * 30,
        maxEntries: 100000,
        riskLevel: CleanupRiskLevel.safe,
        safetyNote: '仅列出 30 天未更新的 Gradle 版本；旧项目再次构建时会重新下载',
      );
      _addExisting(
        targets,
        id: 'gradle-cache',
        label: 'Gradle 可重建构建缓存',
        path: _join(userProfile, <String>['.gradle', 'caches']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
        strategy: CleanupTargetStrategy.staleChildDirectories,
        minimumAgeHours: 24,
        riskLevel: CleanupRiskLevel.safe,
        safetyNote: '只按 24 小时未更新的完整顶层缓存目录列出；始终需人工确认，删除后下次构建会重新下载/生成',
        maxEntries: 100000,
      );
      _addExisting(
        targets,
        id: 'gradle-temp',
        label: 'Gradle 临时下载与构建残留',
        path: _join(userProfile, <String>['.gradle', '.tmp']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
        minimumAgeHours: 1,
        riskLevel: CleanupRiskLevel.safe,
        safetyNote: '只列出 1 小时前的 Gradle 临时文件；构建进程正在使用或文件已变化时删除层会跳过',
        maxEntries: 100000,
      );
      for (final (String id, String label, List<String> parts)
          in <(String, String, List<String>)>[
            ('codex-temp', 'Codex 临时文件', <String>['.codex', '.tmp']),
            ('codex-runtime-temp', 'Codex 运行时临时文件', <String>['.codex', 'tmp']),
            ('codex-cache', 'Codex 可再生缓存', <String>['.codex', 'cache']),
          ]) {
        _addExisting(
          targets,
          id: id,
          label: label,
          path: _join(userProfile, parts),
          category: CleanupCategory.devCache,
          defaultEnabled: true,
          minimumAgeHours: 24,
          riskLevel: CleanupRiskLevel.safe,
          safetyNote: 'Codex 可再生的临时/缓存数据；不扫描 sessions、plugins、skills、凭据或当前工作区',
          maxEntries: 100000,
        );
      }
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
        maxEntries: 100000,
      );
      _addExisting(
        targets,
        id: 'pip-cache',
        label: 'Python pip 下载缓存',
        path: _join(local, <String>['pip', 'Cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
        maxEntries: 100000,
      );
      _addExisting(
        targets,
        id: 'pub-cache',
        label: 'Dart / Flutter Pub 下载缓存',
        path: _join(local, <String>['Pub', 'Cache']),
        category: CleanupCategory.devCache,
        defaultEnabled: true,
        maxEntries: 100000,
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

    _addWindowsCatalogTargets(
      targets,
      env,
      windowsBuild ?? _currentWindowsBuild(environment != null),
    );
    final String? systemDrive = env['SYSTEMDRIVE'];
    if (systemDrive != null && systemDrive.trim().isNotEmpty) {
      _addWindowsUserProfileInventory(
        targets,
        systemDrive.trim(),
        currentProfile: userProfile ?? '',
      );
      targets.add(
        CleanupScanTarget(
          id: 'system-recycle-bin',
          label: '系统回收站',
          path: systemDrive.trim().endsWith(Platform.pathSeparator)
              ? systemDrive.trim()
              : '${systemDrive.trim()}${Platform.pathSeparator}',
          category: CleanupCategory.recycleBin,
          defaultEnabled: true,
          strategy: CleanupTargetStrategy.recycleBin,
          safetyNote: '清空后无法恢复；必须逐项确认，不会自动勾选',
          riskLevel: CleanupRiskLevel.systemManaged,
        ),
      );
      _addWindowsProfileTransientTargets(targets, systemDrive.trim());
      _addExisting(
        targets,
        id: 'system-drive-log-inventory',
        label: '系统盘全部 .log 日志清单',
        path: systemDrive.trim().endsWith(Platform.pathSeparator)
            ? systemDrive.trim()
            : '${systemDrive.trim()}${Platform.pathSeparator}',
        category: CleanupCategory.discoveredTransient,
        defaultEnabled: false,
        safetyNote: '遍历系统盘并列出旧 .log；未知用途日志默认不勾选，需逐项确认',
        minimumAgeHours: 168,
        maxDepth: 16,
        maxEntries: 25000,
        includePatterns: const <String>['*.log'],
      );
    }
    _addHarnessDebugTargets(targets, harnessDebugDirectory);

    return _deduplicate(targets);
  }

  static List<CleanupScanTarget> _deduplicate(List<CleanupScanTarget> targets) {
    final Map<String, CleanupScanTarget> unique = <String, CleanupScanTarget>{};
    for (final CleanupScanTarget target in targets) {
      final String? normalized = CleanupWhitelist.normalize(target.path);
      if (normalized != null) {
        final String pathKey = normalized.toLowerCase();
        // A physical path may intentionally have multiple scanners. For
        // example C:\ is both the recycle-bin pseudo target and the optional
        // full-drive log inventory. Only ordinary directory targets are
        // interchangeable by path.
        final String key =
            target.ruleCatalogVersion == null &&
                target.strategy == CleanupTargetStrategy.directoryContents
            ? pathKey
            : '$pathKey|${target.id}';
        unique[key] = target;
      }
    }
    return unique.values.toList(growable: false);
  }

  static void _addAndroidTargets(
    List<CleanupScanTarget> targets,
    Map<String, String> environment, {
    required String appCacheDirectory,
    required String harnessDebugDirectory,
  }) {
    final List<String> ownedRoots = CleanupPlatformPolicy.androidOwnedRoots(
      environment: environment,
      appCacheDirectory: appCacheDirectory,
      harnessDebugDirectory: harnessDebugDirectory,
    );
    if (ownedRoots.isNotEmpty) {
      _addExisting(
        targets,
        id: 'android-vibekits-app-cache',
        label: 'Vibekits 应用缓存',
        path: ownedRoots.first,
        category: CleanupCategory.applicationCache,
        defaultEnabled: true,
        minimumAgeHours: 24,
        maxDepth: 8,
        maxEntries: 25000,
        safetyNote: '仅本应用私有缓存；不访问共享存储、下载目录或其他应用数据',
        ruleSource: 'Android 应用沙箱规则',
      );
    }
    if (harnessDebugDirectory.trim().isNotEmpty &&
        CleanupPlatformPolicy.isAndroidOwnedPath(
          harnessDebugDirectory,
          environment: environment,
          appCacheDirectory: appCacheDirectory,
          harnessDebugDirectory: harnessDebugDirectory,
        )) {
      _addHarnessDebugTargets(targets, harnessDebugDirectory);
    }
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
        riskLevel: switch (rule.risk) {
          WindowsCleanupRuleRisk.safe => CleanupRiskLevel.safe,
          WindowsCleanupRuleRisk.cautious => CleanupRiskLevel.cautious,
          WindowsCleanupRuleRisk.systemManaged =>
            CleanupRiskLevel.systemManaged,
        },
        ruleSource: 'Windows 规则库 v${WindowsCleanupRuleCatalog.version}',
      );
    }
  }

  /// Finds transient data across every Windows profile, including template
  /// profiles such as `C:\Users\Default`. Discovery is evidence-based and
  /// shallow: it only promotes directories whose name is a well-known
  /// transient token or that directly contain log/dump files. These targets
  /// are scanned by default but every result remains high-risk and unselected.
  static void _addWindowsProfileTransientTargets(
    List<CleanupScanTarget> targets,
    String systemDrive,
  ) {
    final Directory users = Directory(_join(systemDrive, <String>['Users']));
    if (!users.existsSync()) return;
    List<FileSystemEntity> profiles;
    try {
      profiles = users.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    int added = 0;
    for (final FileSystemEntity profile in profiles) {
      if (added >= 64 ||
          FileSystemEntity.typeSync(profile.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        continue;
      }
      final String profileName = _baseName(profile.path);
      for (final String area in <String>['Roaming', 'Local']) {
        final Directory appData = Directory(
          _join(profile.path, <String>['AppData', area]),
        );
        if (!appData.existsSync()) continue;
        added += _discoverTransientChildren(
          targets,
          appData,
          profileName: profileName,
          area: area,
          remaining: 64 - added,
        );
      }
    }
  }

  /// Adds a read-only inventory of Windows profiles other than the current
  /// user. A profile directory is not a cache: it may contain documents, SSH
  /// keys and loaded NTUSER/UsrClass registry hives. Therefore this target is
  /// opt-in and every result is system-managed/protected. It exists so a full
  /// disk report no longer hides multi-gigabyte retired profiles or suggests
  /// that the generic file deleter can safely remove them.
  static void _addWindowsUserProfileInventory(
    List<CleanupScanTarget> targets,
    String systemDrive, {
    required String currentProfile,
  }) {
    final String users = _join(systemDrive, <String>['Users']);
    final String currentName = currentProfile.trim().isEmpty
        ? ''
        : _baseName(currentProfile).toLowerCase();
    _addExisting(
      targets,
      id: 'windows-other-user-profiles',
      label: '其他 Windows 用户配置容量盘点',
      path: users,
      category: CleanupCategory.userProfileResidual,
      defaultEnabled: false,
      strategy: CleanupTargetStrategy.staleChildDirectories,
      maxEntries: 500000,
      excludePatterns: <String>[
        'public',
        'default',
        'default user',
        'all users',
        'defaultuser0',
        if (currentName.isNotEmpty) currentName,
      ],
      riskLevel: CleanupRiskLevel.systemManaged,
      safetyNote: '只读汇总非当前用户目录；不判定账户已废弃，不读文件正文，不提权、不卸载注册表、不进入 10 GiB 自动恢复计划；请先从 Windows 账户/用户配置删除',
    );
  }

  static void _addHarnessDebugTargets(
    List<CleanupScanTarget> targets,
    String configuredRoot,
  ) {
    final String root = configuredRoot.trim();
    if (root.isEmpty || !Directory(root).isAbsolute) return;
    _addExisting(
      targets,
      id: 'harness-debug-logs',
      label: 'Harness 大模型调试日志',
      path: _join(root, <String>['logs']),
      category: CleanupCategory.logs,
      defaultEnabled: true,
      safetyNote: '只清理 24 小时前的 Harness stdout/stderr 日志',
      minimumAgeHours: 24,
      includePatterns: const <String>['*.log'],
    );
    _addExisting(
      targets,
      id: 'harness-debug-screenshots',
      label: 'Harness 大模型调试截图',
      path: _join(root, <String>['screenshots']),
      category: CleanupCategory.debugArtifacts,
      defaultEnabled: true,
      safetyNote: '只清理 24 小时前的调试截图，避免影响当前任务',
      minimumAgeHours: 24,
      includePatterns: const <String>[
        '*.png',
        '*.jpg',
        '*.jpeg',
        '*.webp',
        '*.bmp',
      ],
    );
    _addExisting(
      targets,
      id: 'harness-debug-temp',
      label: 'Harness 大模型临时文件',
      path: _join(root, <String>['temp']),
      category: CleanupCategory.debugArtifacts,
      defaultEnabled: true,
      safetyNote: '只清理 24 小时前的子进程临时文件',
      minimumAgeHours: 24,
    );
  }

  static int _discoverTransientChildren(
    List<CleanupScanTarget> targets,
    Directory root, {
    required String profileName,
    required String area,
    required int remaining,
  }) {
    int added = 0;
    final List<(Directory, int)> pending = <(Directory, int)>[(root, 0)];
    while (pending.isNotEmpty && added < remaining) {
      final (Directory current, int depth) = pending.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false).take(256).toList();
      } on FileSystemException {
        continue;
      }
      for (final FileSystemEntity entry in entries) {
        if (added >= remaining ||
            FileSystemEntity.typeSync(entry.path, followLinks: false) !=
                FileSystemEntityType.directory) {
          continue;
        }
        final Directory directory = Directory(entry.path);
        final String name = _baseName(entry.path).toLowerCase();
        final bool cacheLike = _cacheDirectoryNames.contains(name);
        final bool logNamed = _logDirectoryNames.contains(name);
        final bool containsLogs =
            !cacheLike && _containsDirectLogEvidence(directory);
        if ((cacheLike || logNamed || containsLogs) &&
            !_containsTargetPath(targets, directory.path)) {
          final bool logs = logNamed || containsLogs;
          _addExisting(
            targets,
            id: 'profile-transient-${directory.path.toLowerCase().hashCode.abs()}',
            label:
                '$profileName · AppData/$area · '
                '${logs ? '发现的日志' : '发现的缓存'} · ${_baseName(directory.path)}',
            path: directory.path,
            category: CleanupCategory.discoveredTransient,
            defaultEnabled: true,
            safetyNote: '按目录语义或直接文件证据自动发现；默认不选择，确认应用已关闭后再清理',
            minimumAgeHours: 168,
            maxDepth: 4,
            includePatterns: logs ? _logEvidencePatterns : const <String>[],
            excludePatterns: const <String>[
              '*.db',
              '*.sqlite',
              '*.sqlite3',
              '*.json',
              '*.yaml',
              '*.yml',
              '*.ini',
              '*.conf',
              '*.config',
            ],
          );
          added++;
          continue;
        }
        if (depth < 1) pending.add((directory, depth + 1));
      }
    }
    return added;
  }

  static bool _containsDirectLogEvidence(Directory directory) {
    try {
      int checked = 0;
      for (final FileSystemEntity entry in directory.listSync(
        followLinks: false,
      )) {
        if (++checked > 128) break;
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final String name = _baseName(entry.path).toLowerCase();
        if (_logEvidencePatterns.any(
          (String pattern) => _matchesSimpleExtension(name, pattern),
        )) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  static bool _matchesSimpleExtension(String name, String pattern) =>
      pattern.startsWith('*.') && name.endsWith(pattern.substring(1));

  static bool _containsTargetPath(
    List<CleanupScanTarget> targets,
    String path,
  ) {
    final String? normalized = CleanupWhitelist.normalize(path);
    if (normalized == null) return true;
    final String key = normalized.toLowerCase();
    return targets.any(
      (CleanupScanTarget target) =>
          CleanupWhitelist.normalize(target.path)?.toLowerCase() == key,
    );
  }

  static const Set<String> _cacheDirectoryNames = <String>{
    'cache',
    'caches',
    'code cache',
    'gpucache',
    'dawncache',
    'shadercache',
    'temp',
    'tmp',
  };

  static const Set<String> _logDirectoryNames = <String>{
    'log',
    'logs',
    'logfiles',
    'crash',
    'crashes',
    'crashdumps',
    'dumps',
  };

  static const List<String> _logEvidencePatterns = <String>[
    '*.log',
    '*.etl',
    '*.dmp',
    '*.hprof',
    '*.trace',
    '*.tmp',
    '*.bak',
  ];

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
    int maxEntries = 5000,
    int minimumSizeBytes = 0,
    List<String> includePatterns = const <String>[],
    List<String> excludePatterns = const <String>[],
    int? ruleCatalogVersion,
    CleanupRiskLevel riskLevel = CleanupRiskLevel.safe,
    String ruleSource = '内置规则',
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
        maxEntries: maxEntries,
        minimumSizeBytes: minimumSizeBytes,
        includePatterns: includePatterns,
        excludePatterns: excludePatterns,
        ruleCatalogVersion: ruleCatalogVersion,
        riskLevel: riskLevel,
        ruleSource: ruleSource,
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
        riskLevel: switch (rule.risk) {
          MacosCleanupRuleRisk.safe => CleanupRiskLevel.safe,
          MacosCleanupRuleRisk.cautious => CleanupRiskLevel.cautious,
          MacosCleanupRuleRisk.systemManaged => CleanupRiskLevel.systemManaged,
        },
        ruleSource: 'macOS 规则库 v${MacosCleanupRuleCatalog.version}',
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
