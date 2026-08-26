import 'dart:io';

/// Stable platform-specific locations for persistent data, rebuildable cache
/// and temporary diagnostics. Callers must not derive these from the current
/// working directory.
class PlatformStorageLayout {
  const PlatformStorageLayout({
    required this.platform,
    required this.settingsDirectory,
    required this.modelsDirectory,
    required this.downloadsDirectory,
    required this.cacheDirectory,
    required this.harnessDebugDirectory,
    required this.credentialStoreLabel,
  });

  final String platform;
  final String settingsDirectory;
  final String modelsDirectory;
  final String downloadsDirectory;
  final String cacheDirectory;
  final String harnessDebugDirectory;
  final String credentialStoreLabel;

  String get settingsFile => _join(settingsDirectory, 'settings.json');

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'settings': settingsFile,
    'models': modelsDirectory,
    'downloads': downloadsDirectory,
    'cache': cacheDirectory,
    'harnessDebug': harnessDebugDirectory,
    'credentials': credentialStoreLabel,
  };

  static PlatformStorageLayout current() => resolve(
    operatingSystem: Platform.operatingSystem,
    environment: Platform.environment,
    systemTempPath: Directory.systemTemp.path,
    executablePath: Platform.resolvedExecutable,
  );

  static PlatformStorageLayout resolve({
    required String operatingSystem,
    required Map<String, String> environment,
    required String systemTempPath,
    String executablePath = '',
  }) {
    final String platform = operatingSystem.trim().toLowerCase();
    if (platform == 'windows') {
      final String local = _firstNonEmpty(<String?>[
        environment['LOCALAPPDATA'],
        environment['APPDATA'],
        environment['USERPROFILE'],
      ], fallback: systemTempPath);
      final String data = _join(local, 'Vibekits');
      final String executableDirectory = executablePath.trim().isEmpty
          ? data
          : File(executablePath).parent.path;
      return PlatformStorageLayout(
        platform: 'windows',
        settingsDirectory: data,
        modelsDirectory: _join(data, 'Models'),
        downloadsDirectory: _join(data, 'downloads'),
        cacheDirectory: _join(data, 'cache'),
        harnessDebugDirectory: _join(executableDirectory, 'tmp'),
        credentialStoreLabel: 'Windows Credential Manager',
      );
    }
    if (platform == 'macos') {
      final String home = _firstNonEmpty(<String?>[
        environment['HOME'],
      ], fallback: systemTempPath);
      final String support = _joinAll(<String>[
        home,
        'Library',
        'Application Support',
        'Vibekits',
      ]);
      final String cache = _joinAll(<String>[
        home,
        'Library',
        'Caches',
        'Vibekits',
      ]);
      return PlatformStorageLayout(
        platform: 'macos',
        settingsDirectory: support,
        modelsDirectory: _join(support, 'Models'),
        downloadsDirectory: _join(cache, 'downloads'),
        cacheDirectory: cache,
        harnessDebugDirectory: _joinAll(<String>[
          home,
          'Library',
          'Logs',
          'Vibekits',
          'Harness',
        ]),
        credentialStoreLabel: 'macOS Keychain',
      );
    }
    if (platform == 'android') {
      // On Android Directory.systemTemp is this application's cache folder.
      final String sandbox = _parentPath(systemTempPath);
      final String files = _joinAll(<String>[sandbox, 'files', 'Vibekits']);
      final String cache = _join(systemTempPath, 'Vibekits');
      return PlatformStorageLayout(
        platform: 'android',
        settingsDirectory: files,
        modelsDirectory: _join(files, 'Models'),
        downloadsDirectory: _join(cache, 'downloads'),
        cacheDirectory: cache,
        harnessDebugDirectory: _join(cache, 'Harness'),
        credentialStoreLabel: 'Android Keystore',
      );
    }
    final String data = _join(systemTempPath, 'Vibekits');
    return PlatformStorageLayout(
      platform: platform.isEmpty ? 'unsupported' : platform,
      settingsDirectory: data,
      modelsDirectory: _join(data, 'Models'),
      downloadsDirectory: _join(data, 'downloads'),
      cacheDirectory: _join(data, 'cache'),
      harnessDebugDirectory: _join(data, 'Harness'),
      credentialStoreLabel: '不可用',
    );
  }

  static String _firstNonEmpty(
    Iterable<String?> values, {
    required String fallback,
  }) {
    for (final String? value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  static String _join(String left, String right) =>
      _joinAll(<String>[left, right]);

  static String _parentPath(String value) {
    String normalized = value.replaceAll('\\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final int separator = normalized.lastIndexOf('/');
    if (separator <= 0) return Directory(value).parent.path;
    return normalized.substring(0, separator);
  }

  static String _joinAll(List<String> parts) {
    if (parts.isEmpty) return '';
    String result = parts.first;
    for (final String part in parts.skip(1)) {
      final String clean = part.replaceAll(RegExp(r'^[\\/]+|[\\/]+$'), '');
      if (clean.isEmpty) continue;
      result = '$result${Platform.pathSeparator}$clean';
    }
    return result;
  }
}
