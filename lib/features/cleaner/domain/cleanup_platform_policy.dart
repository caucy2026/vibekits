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

/// 平台能力和删除边界。扫描与报告可以复用；路径发现和删除权限不可复用。
abstract final class CleanupPlatformPolicy {
  static bool supportsSystemWideAnalysis(CleanupPlatform platform) =>
      platform == CleanupPlatform.windows;

  static bool supportsRecycleOrTrash(CleanupPlatform platform) =>
      platform == CleanupPlatform.windows || platform == CleanupPlatform.macos;

  /// Android 只能永久删除本应用的私有缓存/临时目录，不能扫描其他应用。
  static List<String> androidOwnedRoots({
    Map<String, String>? environment,
    String harnessDebugDirectory = '',
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    final List<String> roots = <String>[
      env['VIBEKITS_APP_CACHE'] ?? Directory.systemTemp.path,
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
    String harnessDebugDirectory = '',
  }) => androidOwnedRoots(
    environment: environment,
    harnessDebugDirectory: harnessDebugDirectory,
  ).any((String root) => containsPath(root, path, windows: false));

  /// 执行删除前的最后一道平台边界。发现算法出错时，这一层仍会拒绝越界路径。
  static bool allowsDeletion(
    CleanupPlatform platform,
    String path, {
    Map<String, String>? environment,
    String harnessDebugDirectory = '',
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    switch (platform) {
      case CleanupPlatform.windows:
        final String normalized = path.replaceAll('/', '\\').toLowerCase();
        final String windows = (env['WINDIR'] ?? r'C:\Windows')
            .replaceAll('/', '\\')
            .toLowerCase();
        return !containsPath('$windows\\System32', normalized, windows: true) &&
            !containsPath('$windows\\WinSxS', normalized, windows: true) &&
            !RegExp(r'^[a-z]:\\?$').hasMatch(normalized);
      case CleanupPlatform.macos:
        final String home = (env['HOME'] ?? '').trim();
        if (home.isEmpty) return false;
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
        return roots.any(
          (String root) => containsPath(root, path, windows: false),
        );
      case CleanupPlatform.android:
        return isAndroidOwnedPath(
          path,
          environment: env,
          harnessDebugDirectory: harnessDebugDirectory,
        );
      case CleanupPlatform.linux:
      case CleanupPlatform.unsupported:
        return false;
    }
  }

  static bool containsPath(
    String root,
    String candidate, {
    required bool windows,
  }) {
    String normalize(String value) {
      String result = value.replaceAll('\\', '/');
      while (result.endsWith('/') && result.length > 1) {
        result = result.substring(0, result.length - 1);
      }
      return windows ? result.toLowerCase() : result;
    }

    final String normalizedRoot = normalize(root);
    final String normalizedCandidate = normalize(candidate);
    return normalizedCandidate == normalizedRoot ||
        normalizedCandidate.startsWith('$normalizedRoot/');
  }
}
