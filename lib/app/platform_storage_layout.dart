import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef DirectoryWriteProbe = Future<bool> Function(String path);

class PlatformStorageRoots {
  const PlatformStorageRoots({
    required this.applicationSupport,
    required this.applicationCache,
    required this.temporary,
    required this.documents,
  });

  final String applicationSupport;
  final String applicationCache;
  final String temporary;
  final String documents;
}

class PlatformStorageAccessReport {
  const PlatformStorageAccessReport({
    required this.platform,
    required this.writable,
    required this.fallbacks,
    required this.persistentDataUsesTemporaryStorage,
  });

  final String platform;
  final Map<String, bool> writable;
  final List<String> fallbacks;
  final bool persistentDataUsesTemporaryStorage;

  bool get allRequiredWritable => writable.values.every((bool value) => value);

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'writable': writable,
    'fallbacks': fallbacks,
    'persistentDataUsesTemporaryStorage': persistentDataUsesTemporaryStorage,
    'allRequiredWritable': allRequiredWritable,
  };
}

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

  static PlatformStorageLayout? _runtimeLayout;
  static PlatformStorageAccessReport? _lastAccessReport;

  String get settingsFile => _join(settingsDirectory, 'settings.json');

  static PlatformStorageAccessReport? get lastAccessReport => _lastAccessReport;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'settings': settingsFile,
    'models': modelsDirectory,
    'downloads': downloadsDirectory,
    'cache': cacheDirectory,
    'harnessDebug': harnessDebugDirectory,
    'credentials': credentialStoreLabel,
    if (_lastAccessReport != null) 'access': _lastAccessReport!.toJson(),
  };

  static PlatformStorageLayout current() =>
      _runtimeLayout ??
      resolve(
        operatingSystem: Platform.operatingSystem,
        environment: Platform.environment,
        systemTempPath: Directory.systemTemp.path,
        executablePath: Platform.resolvedExecutable,
      );

  /// Resolves native application roots and proves that every selected location
  /// is actually writable before the rest of the application starts using it.
  static Future<PlatformStorageAccessReport> initialize({
    String? operatingSystem,
    Map<String, String>? environment,
    String? executablePath,
    PlatformStorageRoots? roots,
    DirectoryWriteProbe? writeProbe,
  }) async {
    final String platform = (operatingSystem ?? Platform.operatingSystem)
        .trim()
        .toLowerCase();
    final PlatformStorageRoots nativeRoots = roots ?? await _nativeRoots();
    final DirectoryWriteProbe probe = writeProbe ?? _probeDirectory;
    final List<String> fallbacks = <String>[];

    final String preferredSupport = _appScoped(nativeRoots.applicationSupport);
    final String documentFallback = _appScoped(nativeRoots.documents);
    final String temporaryFallback = _joinAll(<String>[
      nativeRoots.temporary,
      'Vibekits',
      'persistent-recovery',
    ]);
    final _WritableChoice support = await _firstWritable(<String>[
      preferredSupport,
      documentFallback,
      temporaryFallback,
    ], probe);
    if (support.index > 0) {
      fallbacks.add('持久目录不可写，已切换：$preferredSupport → ${support.path}');
    }

    final String preferredCache = _appScoped(nativeRoots.applicationCache);
    final _WritableChoice cache = await _firstWritable(<String>[
      preferredCache,
      _joinAll(<String>[nativeRoots.temporary, 'Vibekits', 'cache']),
    ], probe);
    if (cache.index > 0) {
      fallbacks.add('缓存目录不可写，已切换：$preferredCache → ${cache.path}');
    }

    final Map<String, String> effectiveEnvironment =
        environment ?? Platform.environment;
    final String preferredModels = platform == 'windows'
        ? _joinAll(<String>[
            _firstNonEmpty(<String?>[
              effectiveEnvironment['LOCALAPPDATA'],
              cache.path,
            ], fallback: cache.path),
            'Vibekits',
            'Models',
          ])
        : _join(support.path, 'Models');
    final _WritableChoice models = await _firstWritable(<String>[
      preferredModels,
      _join(cache.path, 'Models'),
    ], probe);
    if (models.index > 0) {
      fallbacks.add('模型目录不可写，已切换：$preferredModels → ${models.path}');
    }

    final String preferredDebug = platform == 'windows'
        ? _joinAll(<String>[
            _parentPath(executablePath ?? Platform.resolvedExecutable),
            'tmp',
          ])
        : platform == 'macos'
        ? _joinAll(<String>[
            _homeFrom(
              environment ?? Platform.environment,
              nativeRoots.documents,
            ),
            'Library',
            'Logs',
            'Vibekits',
            'Harness',
          ])
        : _join(cache.path, 'Harness');
    final _WritableChoice debug = await _firstWritable(<String>[
      preferredDebug,
      _join(cache.path, 'Harness'),
    ], probe);
    if (debug.index > 0) {
      fallbacks.add('调试目录不可写，已切换：$preferredDebug → ${debug.path}');
    }

    final PlatformStorageLayout layout = PlatformStorageLayout(
      platform: platform,
      settingsDirectory: support.path,
      modelsDirectory: models.path,
      downloadsDirectory: _join(cache.path, 'downloads'),
      cacheDirectory: cache.path,
      harnessDebugDirectory: debug.path,
      credentialStoreLabel: _credentialLabel(platform),
    );
    final Map<String, bool> writable = <String, bool>{
      'settings': support.writable,
      'models': models.writable,
      'downloads': await probe(layout.downloadsDirectory),
      'cache': cache.writable,
      'harnessDebug': debug.writable,
    };
    final PlatformStorageAccessReport report = PlatformStorageAccessReport(
      platform: platform,
      writable: Map<String, bool>.unmodifiable(writable),
      fallbacks: List<String>.unmodifiable(fallbacks),
      persistentDataUsesTemporaryStorage: _samePath(
        support.path,
        temporaryFallback,
      ),
    );
    _runtimeLayout = layout;
    _lastAccessReport = report;
    return report;
  }

  static Future<PlatformStorageRoots> _nativeRoots() async {
    Future<String> pathOr(
      Future<Directory> Function() provider,
      String fallback,
    ) async {
      try {
        return (await provider()).path;
      } catch (_) {
        return fallback;
      }
    }

    final String temporary = await pathOr(
      getTemporaryDirectory,
      Directory.systemTemp.path,
    );
    final String support = await pathOr(
      getApplicationSupportDirectory,
      _fallbackSupportPath(temporary),
    );
    final String cache = await pathOr(
      getApplicationCacheDirectory,
      _joinAll(<String>[temporary, 'Vibekits', 'cache']),
    );
    final String documents = await pathOr(
      getApplicationDocumentsDirectory,
      support,
    );
    return PlatformStorageRoots(
      applicationSupport: support,
      applicationCache: cache,
      temporary: temporary,
      documents: documents,
    );
  }

  static Future<bool> _probeDirectory(String path) async {
    if (path.trim().isEmpty) return false;
    final Directory directory = Directory(path);
    final File probe = File(
      _join(
        path,
        '.vibekits-write-probe-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await directory.create(recursive: true);
      const String marker = 'vibekits-storage-ok';
      await probe.writeAsString(marker, flush: true);
      final bool valid = await probe.readAsString() == marker;
      await probe.delete();
      return valid;
    } catch (_) {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
      return false;
    }
  }

  static Future<_WritableChoice> _firstWritable(
    List<String> candidates,
    DirectoryWriteProbe probe,
  ) async {
    final List<String> unique = candidates
        .where((String item) => item.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    for (int index = 0; index < unique.length; index += 1) {
      if (await probe(unique[index])) {
        return _WritableChoice(unique[index], index, true);
      }
    }
    return _WritableChoice(unique.isEmpty ? '' : unique.first, -1, false);
  }

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
          : _parentPath(executablePath);
      return PlatformStorageLayout(
        platform: 'windows',
        settingsDirectory: data,
        modelsDirectory: _join(data, 'Models'),
        downloadsDirectory: _join(data, 'downloads'),
        cacheDirectory: _join(data, 'cache'),
        harnessDebugDirectory: _join(executableDirectory, 'tmp'),
        credentialStoreLabel: _credentialLabel(platform),
      );
    }
    if (platform == 'macos') {
      final String home = _homeFrom(environment, systemTempPath);
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
        credentialStoreLabel: _credentialLabel(platform),
      );
    }
    if (platform == 'android') {
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
        credentialStoreLabel: _credentialLabel(platform),
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
      credentialStoreLabel: _credentialLabel(platform),
    );
  }

  static String _credentialLabel(String platform) => switch (platform) {
    'windows' => 'Windows Credential Manager',
    'macos' => 'macOS Keychain',
    'android' => 'Android Keystore',
    _ => '不可用',
  };

  static String _fallbackSupportPath(String temporary) {
    final Map<String, String> env = Platform.environment;
    if (Platform.isWindows) {
      return _join(
        _firstNonEmpty(<String?>[
          env['LOCALAPPDATA'],
          env['APPDATA'],
          env['USERPROFILE'],
        ], fallback: temporary),
        'Vibekits',
      );
    }
    if (Platform.isMacOS) {
      return _joinAll(<String>[
        _homeFrom(env, temporary),
        'Library',
        'Application Support',
        'Vibekits',
      ]);
    }
    return _joinAll(<String>[_parentPath(temporary), 'files', 'Vibekits']);
  }

  static String _appScoped(String root) {
    final String normalized = root.replaceAll('\\', '/').toLowerCase();
    return normalized.endsWith('/vibekits') ? root : _join(root, 'Vibekits');
  }

  static bool _samePath(String left, String right) =>
      left.replaceAll('\\', '/').toLowerCase() ==
      right.replaceAll('\\', '/').toLowerCase();

  static String _homeFrom(Map<String, String> environment, String fallback) =>
      _firstNonEmpty(<String?>[environment['HOME']], fallback: fallback);

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

class _WritableChoice {
  const _WritableChoice(this.path, this.index, this.writable);

  final String path;
  final int index;
  final bool writable;
}
