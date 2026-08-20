import 'dart:io';

class InstalledApplication {
  const InstalledApplication({
    required this.id,
    required this.name,
    this.publisher = '',
    this.version = '',
    this.installLocation = '',
    this.estimatedSizeBytes = 0,
    this.uninstallCommand = '',
  });

  final String id;
  final String name;
  final String publisher;
  final String version;
  final String installLocation;
  final int estimatedSizeBytes;
  final String uninstallCommand;

  bool get canUninstall => uninstallCommand.trim().isNotEmpty;
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
    return List<InstalledApplication>.unmodifiable(result);
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
}

class _WindowsCommand {
  const _WindowsCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
