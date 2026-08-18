enum WindowsCleanupRuleRisk { safe, cautious, systemManaged }

enum WindowsCleanupRuleCategory { systemCache, logs, applicationCache }

class WindowsCleanupRule {
  const WindowsCleanupRule({
    required this.id,
    required this.label,
    required this.pathTemplate,
    required this.category,
    required this.risk,
    required this.defaultEnabled,
    this.minimumWindowsBuild = 6000,
    this.maximumWindowsBuild,
    this.minimumAgeHours = 24,
    this.includePatterns = const <String>[],
    this.excludePatterns = const <String>[],
    this.note = '',
  });

  final String id;
  final String label;
  final String pathTemplate;
  final WindowsCleanupRuleCategory category;
  final WindowsCleanupRuleRisk risk;
  final bool defaultEnabled;
  final int minimumWindowsBuild;
  final int? maximumWindowsBuild;
  final int minimumAgeHours;
  final List<String> includePatterns;
  final List<String> excludePatterns;
  final String note;

  bool supportsBuild(int build) =>
      build >= minimumWindowsBuild &&
      (maximumWindowsBuild == null || build <= maximumWindowsBuild!);
}

/// Vibekits 自有 Windows 清理规则库。
///
/// 规则只描述明确的瞬态目录，不扫描整盘寻找通用扩展名。系统管理型缓存
/// 默认关闭；下载目录、Windows.old、驱动包、预取和注册表不在直接删除库中。
abstract final class WindowsCleanupRuleCatalog {
  static const int version = 1;

  static const List<WindowsCleanupRule> rules = <WindowsCleanupRule>[
    WindowsCleanupRule(
      id: 'windows-explorer-thumbnail-cache',
      label: 'Windows 缩略图与图标缓存',
      pathTemplate: r'%LOCALAPPDATA%\Microsoft\Windows\Explorer',
      category: WindowsCleanupRuleCategory.systemCache,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 24,
      includePatterns: <String>['thumbcache_*.db', 'iconcache_*.db'],
      note: '资源管理器会按需重建；不删除其他 Explorer 数据',
    ),
    WindowsCleanupRule(
      id: 'windows-inet-cache',
      label: 'Windows Internet 临时缓存',
      pathTemplate: r'%LOCALAPPDATA%\Microsoft\Windows\INetCache',
      category: WindowsCleanupRuleCategory.systemCache,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      note: '可能影响仍在运行的 WebView/旧版浏览器会话，默认不勾选',
    ),
    WindowsCleanupRule(
      id: 'windows-wer-user-archive',
      label: 'Windows 用户错误报告归档',
      pathTemplate: r'%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅已归档诊断报告',
    ),
    WindowsCleanupRule(
      id: 'windows-wer-user-queue',
      label: 'Windows 用户错误报告队列',
      pathTemplate: r'%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 720,
      note: '尚未上报的诊断信息，默认不勾选',
    ),
    WindowsCleanupRule(
      id: 'windows-wer-machine-archive',
      label: 'Windows 系统错误报告归档',
      pathTemplate: r'%PROGRAMDATA%\Microsoft\Windows\WER\ReportArchive',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      note: '系统级诊断报告；可能需要管理员权限',
    ),
    WindowsCleanupRule(
      id: 'windows-wer-machine-queue',
      label: 'Windows 系统错误报告队列',
      pathTemplate: r'%PROGRAMDATA%\Microsoft\Windows\WER\ReportQueue',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.systemManaged,
      defaultEnabled: false,
      minimumAgeHours: 720,
      note: '系统管理的待上报诊断信息，默认不勾选',
    ),
    WindowsCleanupRule(
      id: 'windows-cbs-old-logs',
      label: 'Windows CBS 旧日志',
      pathTemplate: r'%WINDIR%\Logs\CBS',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      includePatterns: <String>['*.log', '*.cab', '*.persist.log'],
      note: '仅一周前日志；排障期间应保留',
    ),
    WindowsCleanupRule(
      id: 'windows-dism-old-logs',
      label: 'Windows DISM 旧日志',
      pathTemplate: r'%WINDIR%\Logs\DISM',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 168,
      includePatterns: <String>['*.log', '*.bak'],
      note: '仅一周前日志；系统映像排障期间应保留',
    ),
    WindowsCleanupRule(
      id: 'windows-panther-old-logs',
      label: 'Windows 安装与升级旧日志',
      pathTemplate: r'%WINDIR%\Panther',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumAgeHours: 720,
      includePatterns: <String>['*.log', '*.etl'],
      note: '升级后 30 天以上才建议；不删除回滚文件',
    ),
    WindowsCleanupRule(
      id: 'windows-update-download-cache',
      label: 'Windows Update 下载缓存',
      pathTemplate: r'%WINDIR%\SoftwareDistribution\Download',
      category: WindowsCleanupRuleCategory.systemCache,
      risk: WindowsCleanupRuleRisk.systemManaged,
      defaultEnabled: false,
      minimumAgeHours: 168,
      note: '系统服务管理目录；仅列出，不默认选择',
    ),
    WindowsCleanupRule(
      id: 'delivery-optimization-cache',
      label: 'Windows 传递优化缓存',
      pathTemplate: r'%WINDIR%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache',
      category: WindowsCleanupRuleCategory.systemCache,
      risk: WindowsCleanupRuleRisk.systemManaged,
      defaultEnabled: false,
      minimumWindowsBuild: 10240,
      minimumAgeHours: 168,
      note: 'Windows 10/11 系统管理缓存；后续优先接系统清理 API',
    ),
    WindowsCleanupRule(
      id: 'nvidia-dx-cache',
      label: 'NVIDIA DirectX 着色器缓存',
      pathTemplate: r'%LOCALAPPDATA%\NVIDIA\DXCache',
      category: WindowsCleanupRuleCategory.applicationCache,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 24,
      note: '驱动会重建；首次启动游戏可能重新编译着色器',
    ),
    WindowsCleanupRule(
      id: 'nvidia-gl-cache',
      label: 'NVIDIA OpenGL 着色器缓存',
      pathTemplate: r'%LOCALAPPDATA%\NVIDIA\GLCache',
      category: WindowsCleanupRuleCategory.applicationCache,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 24,
      note: '驱动会重建',
    ),
    WindowsCleanupRule(
      id: 'vscode-logs',
      label: 'Visual Studio Code 旧日志',
      pathTemplate: r'%APPDATA%\Code\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅一周前诊断日志',
    ),
    WindowsCleanupRule(
      id: 'cursor-logs',
      label: 'Cursor 旧日志',
      pathTemplate: r'%APPDATA%\Cursor\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅一周前诊断日志',
    ),
    WindowsCleanupRule(
      id: 'windsurf-logs',
      label: 'Windsurf 旧日志',
      pathTemplate: r'%APPDATA%\Windsurf\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅一周前诊断日志',
    ),
    WindowsCleanupRule(
      id: 'discord-logs',
      label: 'Discord 旧日志',
      pathTemplate: r'%APPDATA%\discord\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '仅一周前诊断日志',
    ),
    WindowsCleanupRule(
      id: 'docker-desktop-logs',
      label: 'Docker Desktop 旧日志',
      pathTemplate: r'%LOCALAPPDATA%\Docker\log',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '不触碰镜像、容器、卷和 WSL 数据',
    ),
    WindowsCleanupRule(
      id: 'github-desktop-logs',
      label: 'GitHub Desktop 旧日志',
      pathTemplate: r'%APPDATA%\GitHub Desktop\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '不触碰仓库和 Git 配置',
    ),
    WindowsCleanupRule(
      id: 'postman-logs',
      label: 'Postman 旧日志',
      pathTemplate: r'%APPDATA%\Postman\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '不触碰工作区、环境和请求数据',
    ),
    WindowsCleanupRule(
      id: 'slack-logs',
      label: 'Slack 旧日志',
      pathTemplate: r'%APPDATA%\Slack\logs',
      category: WindowsCleanupRuleCategory.logs,
      risk: WindowsCleanupRuleRisk.safe,
      defaultEnabled: true,
      minimumAgeHours: 168,
      note: '不触碰登录和工作区配置',
    ),
    WindowsCleanupRule(
      id: 'teams-classic-cache',
      label: 'Microsoft Teams Classic 缓存',
      pathTemplate: r'%APPDATA%\Microsoft\Teams\Cache',
      category: WindowsCleanupRuleCategory.applicationCache,
      risk: WindowsCleanupRuleRisk.cautious,
      defaultEnabled: false,
      minimumWindowsBuild: 7600,
      minimumAgeHours: 168,
      note: '应用运行时可能占用；默认不勾选',
    ),
  ];
}
