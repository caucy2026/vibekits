enum MacosCleanupRuleRisk { safe, cautious, systemManaged }

enum MacosCleanupRuleCategory {
  browserCache,
  applicationCache,
  developerCache,
  logs,
}

class MacosCleanupRule {
  const MacosCleanupRule({
    required this.id,
    required this.label,
    required this.relativePath,
    required this.category,
    required this.risk,
    required this.defaultEnabled,
    this.minimumMacosMajor = 10,
    this.minimumAgeHours = 24,
    this.maxDepth = 8,
    this.includePatterns = const <String>[],
    this.excludePatterns = const <String>[],
    this.note = '',
  });

  final String id;
  final String label;
  final List<String> relativePath;
  final MacosCleanupRuleCategory category;
  final MacosCleanupRuleRisk risk;
  final bool defaultEnabled;
  final int minimumMacosMajor;
  final int minimumAgeHours;
  final int maxDepth;
  final List<String> includePatterns;
  final List<String> excludePatterns;
  final String note;

  bool supportsMajor(int major) => major >= minimumMacosMajor;
}

/// Vibekits macOS cleanup database, influenced by the data-driven rule models
/// used by Kudu and BitCleanerX while retaining Vibekits' age/risk safeguards.
abstract final class MacosCleanupRuleCatalog {
  static const int version = 1;

  static const List<MacosCleanupRule> rules = <MacosCleanupRule>[
    MacosCleanupRule(
      id: 'mac-xcode-derived-data',
      label: 'Xcode DerivedData',
      relativePath: <String>['Library', 'Developer', 'Xcode', 'DerivedData'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '构建索引和产物可重建；不会触碰 Archives 或项目源码',
    ),
    MacosCleanupRule(
      id: 'mac-xcode-cache',
      label: 'Xcode 应用缓存',
      relativePath: <String>['Library', 'Caches', 'com.apple.dt.Xcode'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: 'Xcode 可重新生成',
    ),
    MacosCleanupRule(
      id: 'mac-core-simulator-cache',
      label: 'CoreSimulator 缓存',
      relativePath: <String>['Library', 'Developer', 'CoreSimulator', 'Caches'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '只清缓存，不删除模拟器设备、运行时和应用数据',
    ),
    MacosCleanupRule(
      id: 'mac-core-simulator-logs',
      label: 'CoreSimulator 旧日志',
      relativePath: <String>['Library', 'Logs', 'CoreSimulator'],
      category: MacosCleanupRuleCategory.logs,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅一周前模拟器日志',
    ),
    MacosCleanupRule(
      id: 'mac-swiftpm-cache',
      label: 'Swift Package Manager 缓存',
      relativePath: <String>['Library', 'Caches', 'org.swift.swiftpm'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '依赖可重新下载',
    ),
    MacosCleanupRule(
      id: 'mac-swiftpm-user-cache',
      label: 'SwiftPM 用户缓存',
      relativePath: <String>['.swiftpm', 'cache'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰 Package.swift 和项目 checkout',
    ),
    MacosCleanupRule(
      id: 'mac-homebrew-cache',
      label: 'Homebrew 下载缓存',
      relativePath: <String>['Library', 'Caches', 'Homebrew'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '仅下载缓存，不删除已安装 formula/cask',
    ),
    MacosCleanupRule(
      id: 'mac-cocoapods-cache',
      label: 'CocoaPods 下载缓存',
      relativePath: <String>['Library', 'Caches', 'CocoaPods'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰项目 Pods 目录和 Podfile.lock',
    ),
    MacosCleanupRule(
      id: 'mac-pip-cache',
      label: 'Python pip 下载缓存',
      relativePath: <String>['Library', 'Caches', 'pip'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
    ),
    MacosCleanupRule(
      id: 'mac-gradle-cache',
      label: 'Gradle 构建与下载缓存',
      relativePath: <String>['.gradle', 'caches'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      note: '可能导致下次 Android/Gradle 构建重新下载和编译',
    ),
    MacosCleanupRule(
      id: 'mac-pub-cache',
      label: 'Dart / Flutter Pub 缓存',
      relativePath: <String>['.pub-cache'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      note: '可能导致下次构建重新下载依赖',
    ),
    MacosCleanupRule(
      id: 'mac-cargo-download-cache',
      label: 'Rust Cargo 下载缓存',
      relativePath: <String>['.cargo', 'registry', 'cache'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
    ),
    MacosCleanupRule(
      id: 'mac-go-download-cache',
      label: 'Go 模块下载缓存',
      relativePath: <String>['go', 'pkg', 'mod', 'cache', 'download'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
    ),
    MacosCleanupRule(
      id: 'mac-npm-cache',
      label: 'npm 下载缓存',
      relativePath: <String>['.npm', '_cacache'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
    ),
    MacosCleanupRule(
      id: 'mac-yarn-cache',
      label: 'Yarn 下载缓存',
      relativePath: <String>['Library', 'Caches', 'Yarn'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
    ),
    MacosCleanupRule(
      id: 'mac-pnpm-cache',
      label: 'pnpm Store 下载缓存',
      relativePath: <String>['Library', 'pnpm', 'store'],
      category: MacosCleanupRuleCategory.developerCache,
      risk: MacosCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      note: '只扫描 store，不触碰项目 node_modules',
    ),
    MacosCleanupRule(
      id: 'mac-vscode-cache',
      label: 'Visual Studio Code 缓存',
      relativePath: <String>['Library', 'Application Support', 'Code', 'Cache'],
      category: MacosCleanupRuleCategory.applicationCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰设置、扩展和工作区',
    ),
    MacosCleanupRule(
      id: 'mac-cursor-cache',
      label: 'Cursor 缓存',
      relativePath: <String>[
        'Library',
        'Application Support',
        'Cursor',
        'Cache',
      ],
      category: MacosCleanupRuleCategory.applicationCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰设置、扩展和工作区',
    ),
    MacosCleanupRule(
      id: 'mac-windsurf-cache',
      label: 'Windsurf 缓存',
      relativePath: <String>[
        'Library',
        'Application Support',
        'Windsurf',
        'Cache',
      ],
      category: MacosCleanupRuleCategory.applicationCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰设置、扩展和工作区',
    ),
    MacosCleanupRule(
      id: 'mac-discord-cache',
      label: 'Discord 缓存',
      relativePath: <String>[
        'Library',
        'Application Support',
        'discord',
        'Cache',
      ],
      category: MacosCleanupRuleCategory.applicationCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰登录、Local Storage 和会话',
    ),
    MacosCleanupRule(
      id: 'mac-docker-old-logs',
      label: 'Docker Desktop 旧日志',
      relativePath: <String>[
        'Library',
        'Containers',
        'com.docker.docker',
        'Data',
        'log',
      ],
      category: MacosCleanupRuleCategory.logs,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '不触碰镜像、容器、卷和虚拟磁盘',
    ),
    MacosCleanupRule(
      id: 'mac-diagnostic-reports',
      label: 'macOS 旧诊断报告',
      relativePath: <String>['Library', 'Logs', 'DiagnosticReports'],
      category: MacosCleanupRuleCategory.logs,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅一周前本机应用崩溃诊断报告',
    ),
    MacosCleanupRule(
      id: 'mac-crash-reporter-data',
      label: 'macOS 旧 CrashReporter 数据',
      relativePath: <String>['Library', 'Application Support', 'CrashReporter'],
      category: MacosCleanupRuleCategory.logs,
      risk: MacosCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 720,
      note: '30 天前诊断数据；排障期间保留',
    ),
    MacosCleanupRule(
      id: 'mac-chrome-cache',
      label: 'Google Chrome 缓存',
      relativePath: <String>['Library', 'Caches', 'Google', 'Chrome'],
      category: MacosCleanupRuleCategory.browserCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰 Cookies、密码、书签和会话',
    ),
    MacosCleanupRule(
      id: 'mac-edge-cache',
      label: 'Microsoft Edge 缓存',
      relativePath: <String>['Library', 'Caches', 'Microsoft Edge'],
      category: MacosCleanupRuleCategory.browserCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '不触碰 Cookies、密码、书签和会话',
    ),
    MacosCleanupRule(
      id: 'mac-firefox-cache',
      label: 'Mozilla Firefox 缓存',
      relativePath: <String>['Library', 'Caches', 'Firefox', 'Profiles'],
      category: MacosCleanupRuleCategory.browserCache,
      risk: MacosCleanupRuleRisk.safe,
      defaultEnabled: true,
      note: '仅 Library/Caches，不触碰配置文件和会话数据',
    ),
  ];
}
