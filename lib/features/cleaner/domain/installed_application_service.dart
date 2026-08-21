import 'dart:io';
import 'dart:isolate';

class InstalledApplication {
  const InstalledApplication({
    required this.id,
    required this.name,
    this.publisher = '',
    this.version = '',
    this.installLocation = '',
    this.estimatedSizeBytes = 0,
    this.uninstallCommand = '',
    this.installedAt,
    this.lastUsedAt,
    this.usageEvidence = '',
  });

  final String id;
  final String name;
  final String publisher;
  final String version;
  final String installLocation;
  final int estimatedSizeBytes;
  final String uninstallCommand;
  final DateTime? installedAt;
  final DateTime? lastUsedAt;
  final String usageEvidence;

  bool get canUninstall => uninstallCommand.trim().isNotEmpty;

  bool unusedForSixMonthsAt(DateTime now) =>
      lastUsedAt != null && now.difference(lastUsedAt!).inDays >= 183;

  InstalledApplication withUsage({
    required DateTime lastUsedAt,
    required String evidence,
  }) => InstalledApplication(
    id: id,
    name: name,
    publisher: publisher,
    version: version,
    installLocation: installLocation,
    estimatedSizeBytes: estimatedSizeBytes,
    uninstallCommand: uninstallCommand,
    installedAt: installedAt,
    lastUsedAt: lastUsedAt,
    usageEvidence: evidence,
  );
}

abstract final class InstalledApplicationService {
  static const List<String> _registryRoots = <String>[
    r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  ];

  static Future<List<InstalledApplication>> load() async {
    if (!Platform.isWindows) return const <InstalledApplication>[];
    final List<List<InstalledApplication>> views = await Future.wait(
      _registryRoots.map(_loadRegistryRoot),
    );
    final List<InstalledApplication> discovered = views
        .expand((List<InstalledApplication> view) => view)
        .toList(growable: false);
    final Map<String, InstalledApplication> unique =
        <String, InstalledApplication>{};
    for (final InstalledApplication app in discovered) {
      final String key = normalizeOwner(app.name);
      if (key.isEmpty) continue;
      final InstalledApplication? previous = unique[key];
      if (previous == null || _score(app) > _score(previous)) {
        unique[key] = app;
      }
    }
    final List<InstalledApplication> result = unique.values.toList()
      ..sort(
        (InstalledApplication left, InstalledApplication right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    final List<InstalledApplication> enriched = await Isolate.run(
      () => _attachPrefetchUsage(result),
    );
    return List<InstalledApplication>.unmodifiable(enriched);
  }

  static Future<List<InstalledApplication>> _loadRegistryRoot(
    String root,
  ) async {
    try {
      final ProcessResult result = await Process.run('reg.exe', <String>[
        'query',
        root,
        '/s',
      ], runInShell: false).timeout(const Duration(seconds: 12));
      if (result.exitCode == 0) {
        return parseRegistryQuery(result.stdout.toString());
      }
    } on Object {
      // A missing/locked registry view must not block storage analysis.
    }
    return const <InstalledApplication>[];
  }

  static List<InstalledApplication> parseRegistryQuery(String output) {
    final List<InstalledApplication> result = <InstalledApplication>[];
    String key = '';
    final Map<String, String> values = <String, String>{};

    void flush() {
      final String name = values['DisplayName']?.trim() ?? '';
      final bool hidden = values['SystemComponent']?.trim() == '0x1';
      if (key.isNotEmpty && name.isNotEmpty && !hidden) {
        final int estimatedKb =
            int.tryParse(values['EstimatedSize']?.trim() ?? '') ?? 0;
        result.add(
          InstalledApplication(
            id: key,
            name: name,
            publisher: values['Publisher']?.trim() ?? '',
            version: values['DisplayVersion']?.trim() ?? '',
            installLocation: _unquote(values['InstallLocation']?.trim() ?? ''),
            estimatedSizeBytes: estimatedKb * 1024,
            uninstallCommand:
                values['QuietUninstallString']?.trim().isNotEmpty == true
                ? values['QuietUninstallString']!.trim()
                : values['UninstallString']?.trim() ?? '',
            installedAt: _parseInstallDate(values['InstallDate']?.trim() ?? ''),
          ),
        );
      }
      values.clear();
    }

    final RegExp valuePattern = RegExp(
      r'^\s{2,}([^\s]+)\s+REG_[A-Z0-9_]+\s*(.*)$',
    );
    for (final String rawLine in output.split(RegExp(r'\r?\n'))) {
      final String line = rawLine.trimRight();
      if (line.trimLeft().startsWith('HKEY_')) {
        flush();
        key = line.trim();
        continue;
      }
      final RegExpMatch? match = valuePattern.firstMatch(line);
      if (match != null) values[match.group(1)!] = match.group(2) ?? '';
    }
    flush();
    return result;
  }

  static Future<bool> launchUninstaller(InstalledApplication app) async {
    if (!Platform.isWindows || !app.canUninstall) return false;
    final _WindowsCommand? command = _parseCommand(app.uninstallCommand);
    if (command == null) return false;
    try {
      final String executable = _expandEnvironment(command.executable);
      final List<String> arguments = <String>[...command.arguments];
      if (_baseName(executable).toLowerCase() == 'msiexec.exe' ||
          _baseName(executable).toLowerCase() == 'msiexec') {
        for (int index = 0; index < arguments.length; index++) {
          final String lower = arguments[index].toLowerCase();
          if (lower == '/i' || lower.startsWith('/i{')) {
            arguments[index] = '/x${arguments[index].substring(2)}';
            break;
          }
        }
      }
      await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } on Object {
      return false;
    }
  }

  static _WindowsCommand? _parseCommand(String raw) {
    final String command = raw.trim();
    if (command.isEmpty || command.contains('\u0000')) return null;
    if (command.startsWith('"')) {
      final int closing = command.indexOf('"', 1);
      if (closing <= 1) return null;
      return _WindowsCommand(
        command.substring(1, closing),
        _splitArguments(command.substring(closing + 1)),
      );
    }
    final RegExpMatch? executableMatch = RegExp(
      r'^(.+?\.exe)(?:\s+(.*))?$',
      caseSensitive: false,
    ).firstMatch(command);
    if (executableMatch == null) return null;
    return _WindowsCommand(
      executableMatch.group(1)!.trim(),
      _splitArguments(executableMatch.group(2) ?? ''),
    );
  }

  static List<String> _splitArguments(String raw) {
    final List<String> result = <String>[];
    final StringBuffer current = StringBuffer();
    bool quoted = false;
    for (int index = 0; index < raw.length; index++) {
      final String char = raw[index];
      if (char == '"') {
        quoted = !quoted;
      } else if (!quoted && char.trim().isEmpty) {
        if (current.isNotEmpty) {
          result.add(current.toString());
          current.clear();
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) result.add(current.toString());
    return result;
  }

  static String normalizeOwner(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(x64|x86|64-bit|32-bit|version|v)\b'), ' ')
      .replaceAll(RegExp(r'\b\d+(?:\.\d+)+\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
      .trim();

  static int _score(InstalledApplication app) =>
      (app.canUninstall ? 4 : 0) +
      (app.installLocation.isNotEmpty ? 2 : 0) +
      (app.estimatedSizeBytes > 0 ? 1 : 0);

  static DateTime? _parseInstallDate(String value) {
    final RegExpMatch? match = RegExp(r'^(\d{4})(\d{2})(\d{2})$')
        .firstMatch(value);
    if (match == null) return null;
    return DateTime.tryParse(
      '${match.group(1)}-${match.group(2)}-${match.group(3)}',
    );
  }

  static List<InstalledApplication> _attachPrefetchUsage(
    List<InstalledApplication> apps,
  ) {
    final String windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final Directory prefetch = Directory(
      '$windows${Platform.pathSeparator}Prefetch',
    );
    if (!prefetch.existsSync()) return apps;
    final Map<String, DateTime> launches = <String, DateTime>{};
    try {
      for (final FileSystemEntity entity in prefetch.listSync(
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.pf')) {
          continue;
        }
        final String fileName = _baseName(entity.path).toUpperCase();
        final RegExpMatch? match = RegExp(r'^(.+)-[0-9A-F]+\.PF$')
            .firstMatch(fileName);
        if (match == null) continue;
        final String executable = match.group(1)!;
        final DateTime modified = entity.lastModifiedSync();
        final DateTime? previous = launches[executable];
        if (previous == null || modified.isAfter(previous)) {
          launches[executable] = modified;
        }
      }
    } on FileSystemException {
      return apps;
    }
    return <InstalledApplication>[
      for (final InstalledApplication app in apps) _enrichApp(app, launches),
    ];
  }

  static InstalledApplication _enrichApp(
    InstalledApplication app,
    Map<String, DateTime> launches,
  ) {
    final String location = app.installLocation.trim();
    if (location.isEmpty || !Directory(location).existsSync()) return app;
    final Set<String> executableNames = <String>{};
    int visited = 0;
    try {
      // Prefetch enrichment runs while the analysis result is being prepared.
      // Only inspect the installation root: recursively walking SDKs, IDEs and
      // game directories made opening the cleaner take tens of seconds.
      for (final FileSystemEntity entity in Directory(
        location,
      ).listSync(followLinks: false)) {
        if (++visited > 120) break;
        if (entity is! File || !entity.path.toLowerCase().endsWith('.exe')) {
          continue;
        }
        final String name = _baseName(entity.path).toUpperCase();
        final String lower = name.toLowerCase();
        if (lower.contains('unins') ||
            lower.contains('uninstall') ||
            lower.contains('update') ||
            lower.contains('crash') ||
            lower.contains('setup')) {
          continue;
        }
        executableNames.add(name);
      }
    } on FileSystemException {
      return app;
    }
    DateTime? latest;
    String? matchedExecutable;
    for (final String executable in executableNames) {
      final DateTime? used = launches[executable];
      if (used != null && (latest == null || used.isAfter(latest))) {
        latest = used;
        matchedExecutable = executable;
      }
    }
    if (latest == null) {
      final Set<String> identities = <String>{
        _usageToken(app.name),
        _usageToken(_baseName(location)),
      }..removeWhere((String value) => value.length < 5);
      for (final MapEntry<String, DateTime> launch in launches.entries) {
        final String launchToken = _usageToken(launch.key);
        final bool matches = identities.any(
          (String identity) =>
              launchToken == identity ||
              launchToken.contains(identity) ||
              identity.contains(launchToken),
        );
        if (matches && (latest == null || launch.value.isAfter(latest))) {
          latest = launch.value;
          matchedExecutable = launch.key;
        }
      }
    }
    return latest == null
        ? app
        : app.withUsage(
            lastUsedAt: latest,
            evidence: 'Windows Prefetch · $matchedExecutable',
          );
  }

  static String _unquote(String value) =>
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
      ? value.substring(1, value.length - 1)
      : value;

  static String _expandEnvironment(String value) => value.replaceAllMapped(
    RegExp(r'%([^%]+)%'),
    (Match match) =>
        Platform.environment[match.group(1)] ?? match.group(0) ?? '',
  );

  static String _baseName(String path) =>
      path.replaceAll('/', '\\').split('\\').last;

  static String _usageToken(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\.exe$'), '')
      .replaceAll(RegExp(r'\b(x64|x86|64bit|32bit)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _WindowsCommand {
  const _WindowsCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
