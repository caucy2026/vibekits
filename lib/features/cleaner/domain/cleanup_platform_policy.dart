import 'dart:io';

/// 清理器支持的平台。平台值可以在测试中注入，避免用宿主系统冒充目标系统。
enum CleanupPlatform {
  windows('windows', 'Windows'),
  macos('macos', 'macOS'),
  android('android', 'Android'),
  linux('linux', 'Linux'),
  unsupported('unsupported', '不支持的平台');

  const CleanupPlatform(this.wireName, this.label);

  final String wireName;
  final String label;

  static CleanupPlatform get current => fromName(Platform.operatingSystem);

  static CleanupPlatform fromName(String value) =>
      switch (value.trim().toLowerCase()) {
        'windows' => CleanupPlatform.windows,
        'macos' => CleanupPlatform.macos,
        'android' => CleanupPlatform.android,
        'linux' => CleanupPlatform.linux,
        _ => CleanupPlatform.unsupported,
      };
}

class CleanupPlatformCapabilities {
  const CleanupPlatformCapabilities({
    required this.platform,
    required this.scanScope,
    required this.deletionMode,
    required this.supportsSystemWideAnalysis,
    required this.supportsMultipleVolumes,
    required this.supportsInstalledAppInventory,
    required this.supportsUninstall,
    required this.supportsRecycleOrTrash,
  });

  final CleanupPlatform platform;
  final String scanScope;
  final String deletionMode;
  final bool supportsSystemWideAnalysis;
  final bool supportsMultipleVolumes;
  final bool supportsInstalledAppInventory;
  final bool supportsUninstall;
  final bool supportsRecycleOrTrash;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform.wireName,
    'scanScope': scanScope,
    'deletionMode': deletionMode,
    'systemWideAnalysis': supportsSystemWideAnalysis,
    'multipleVolumes': supportsMultipleVolumes,
    'installedAppInventory': supportsInstalledAppInventory,
    'uninstall': supportsUninstall,
    'recycleOrTrash': supportsRecycleOrTrash,
  };
}

/// 平台能力和删除边界。扫描与报告可以复用；路径发现和删除权限不可复用。
abstract final class CleanupPlatformPolicy {
  static CleanupPlatformCapabilities capabilities(CleanupPlatform platform) =>
      switch (platform) {
        CleanupPlatform.windows => const CleanupPlatformCapabilities(
          platform: CleanupPlatform.windows,
          scanScope: '所选本地磁盘、Windows 系统缓存、应用缓存、开发缓存与日志',
          deletionMode: '安全项永久删除；谨慎项由用户确认；系统管理目录始终保护',
          supportsSystemWideAnalysis: true,
          supportsMultipleVolumes: true,
          supportsInstalledAppInventory: true,
          supportsUninstall: true,
          supportsRecycleOrTrash: true,
        ),
        CleanupPlatform.macos => const CleanupPlatformCapabilities(
          platform: CleanupPlatform.macos,
          scanScope: '当前用户 Library 缓存/日志、开发工具缓存和明确的应用缓存',
          deletionMode: '仅规则库允许的用户目录；谨慎项进入废纸篓；系统目录不扫描',
          supportsSystemWideAnalysis: false,
          supportsMultipleVolumes: false,
          supportsInstalledAppInventory: false,
          supportsUninstall: false,
          supportsRecycleOrTrash: true,
        ),
        CleanupPlatform.android => const CleanupPlatformCapabilities(
          platform: CleanupPlatform.android,
          scanScope: '仅 Vibekits 应用私有 cache/tmp、Harness 日志和调试截图',
          deletionMode: '应用沙箱内永久删除；共享存储、下载目录、系统和其他应用始终保护',
          supportsSystemWideAnalysis: false,
          supportsMultipleVolumes: false,
          supportsInstalledAppInventory: false,
          supportsUninstall: false,
          supportsRecycleOrTrash: false,
        ),
        CleanupPlatform.linux => const CleanupPlatformCapabilities(
          platform: CleanupPlatform.linux,
          scanScope: '当前版本不执行清理',
          deletionMode: '只读能力说明',
          supportsSystemWideAnalysis: false,
          supportsMultipleVolumes: false,
          supportsInstalledAppInventory: false,
          supportsUninstall: false,
          supportsRecycleOrTrash: false,
        ),
        CleanupPlatform.unsupported => const CleanupPlatformCapabilities(
          platform: CleanupPlatform.unsupported,
          scanScope: '当前平台未登记',
          deletionMode: '拒绝删除',
          supportsSystemWideAnalysis: false,
          supportsMultipleVolumes: false,
          supportsInstalledAppInventory: false,
          supportsUninstall: false,
          supportsRecycleOrTrash: false,
        ),
      };

  static bool supportsSystemWideAnalysis(CleanupPlatform platform) =>
      capabilities(platform).supportsSystemWideAnalysis;

  static bool supportsRecycleOrTrash(CleanupPlatform platform) =>
      capabilities(platform).supportsRecycleOrTrash;

  /// Android 只能永久删除本应用的私有缓存/临时目录，不能扫描其他应用。
  static List<String> androidOwnedRoots({
    Map<String, String>? environment,
    String appCacheDirectory = '',
    String harnessDebugDirectory = '',
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    final List<String> roots = <String>[
      appCacheDirectory.trim().isNotEmpty
          ? appCacheDirectory
          : env['VIBEKITS_APP_CACHE'] ?? Directory.systemTemp.path,
      env['VIBEKITS_APP_TEMP'] ?? '',
      harnessDebugDirectory,
    ];
    return roots
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static bool isAndroidOwnedPath(
    String path, {
    Map<String, String>? environment,
    String appCacheDirectory = '',
    String harnessDebugDirectory = '',
  }) => androidOwnedRoots(
    environment: environment,
    appCacheDirectory: appCacheDirectory,
    harnessDebugDirectory: harnessDebugDirectory,
  ).any((String root) => containsPath(root, path, windows: false));

  /// 执行删除前的最后一道平台边界。发现算法出错时，这一层仍会拒绝越界路径。
  static bool allowsDeletion(
    CleanupPlatform platform,
    String path, {
    Map<String, String>? environment,
    String appCacheDirectory = '',
    String harnessDebugDirectory = '',
  }) {
    return deletionPredicate(
      platform,
      environment: environment,
      appCacheDirectory: appCacheDirectory,
      harnessDebugDirectory: harnessDebugDirectory,
    )(path);
  }

  /// Builds the platform boundary once for a batch scan. This avoids repeatedly
  /// normalizing the same protected roots for every discovered candidate.
  static bool Function(String path) deletionPredicate(
    CleanupPlatform platform, {
    Map<String, String>? environment,
    String appCacheDirectory = '',
    String harnessDebugDirectory = '',
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    switch (platform) {
      case CleanupPlatform.windows:
        final String windows = (env['WINDIR'] ?? r'C:\Windows')
            .replaceAll('/', '\\')
            .toLowerCase();
        final String system32 = _normalizePath(
          '$windows\\System32',
          windows: true,
        );
        final String winsxs = _normalizePath('$windows\\WinSxS', windows: true);
        return (String path) {
          final String normalized = _normalizePath(path, windows: true);
          return !_containsNormalized(system32, normalized) &&
              !_containsNormalized(winsxs, normalized) &&
              !_isWindowsDriveRoot(normalized);
        };
      case CleanupPlatform.macos:
        final String home = (env['HOME'] ?? '').trim();
        if (home.isEmpty) return (_) => false;
        final List<String> roots = <String>[
          '$home/Library/Caches',
          '$home/Library/Logs',
          '$home/Library/Developer',
          '$home/Library/Application Support/CrashReporter',
          '$home/Library/Application Support/Code/Cache',
          '$home/Library/Application Support/Cursor/Cache',
          '$home/Library/Application Support/Windsurf/Cache',
          '$home/Library/Application Support/discord/Cache',
          '$home/Library/Containers/com.docker.docker/Data/log',
          '$home/.gradle/caches',
          '$home/.pub-cache',
          '$home/.cargo/registry/cache',
          '$home/.npm/_cacache',
          '$home/.swiftpm/cache',
          '$home/go/pkg/mod/cache/download',
          harnessDebugDirectory,
        ].where((String root) => root.trim().isNotEmpty).toList();
        final List<String> normalizedRoots = roots
            .map((String root) => _normalizePath(root, windows: false))
            .toList(growable: false);
        return (String path) {
          final String normalized = _normalizePath(path, windows: false);
          return normalizedRoots.any(
            (String root) => _containsNormalized(root, normalized),
          );
        };
      case CleanupPlatform.android:
        final List<String> normalizedRoots =
            androidOwnedRoots(
                  environment: env,
                  appCacheDirectory: appCacheDirectory,
                  harnessDebugDirectory: harnessDebugDirectory,
                )
                .map((String root) => _normalizePath(root, windows: false))
                .toList(growable: false);
        return (String path) {
          final String normalized = _normalizePath(path, windows: false);
          return normalizedRoots.any(
            (String root) => _containsNormalized(root, normalized),
          );
        };
      case CleanupPlatform.linux:
      case CleanupPlatform.unsupported:
        return (_) => false;
    }
  }

  static bool containsPath(
    String root,
    String candidate, {
    required bool windows,
  }) {
    final String normalizedRoot = _normalizePath(root, windows: windows);
    final String normalizedCandidate = _normalizePath(
      candidate,
      windows: windows,
    );
    return _containsNormalized(normalizedRoot, normalizedCandidate);
  }

  static String _normalizePath(String value, {required bool windows}) {
    String result = value.replaceAll('\\', '/');
    while (result.endsWith('/') && result.length > 1) {
      result = result.substring(0, result.length - 1);
    }
    return windows ? result.toLowerCase() : result;
  }

  static bool _containsNormalized(String root, String candidate) =>
      candidate == root || candidate.startsWith('$root/');

  static bool _isWindowsDriveRoot(String path) =>
      path.length == 2 && path.codeUnitAt(1) == 58;
}
