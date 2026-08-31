import 'dart:io';

import 'platform_storage_layout.dart';

abstract final class AppCrashLog {
  static const int maxBytes = 512 * 1024;

  static File get file => File(
    '${PlatformStorageLayout.current().cacheDirectory}'
    '${Platform.pathSeparator}logs${Platform.pathSeparator}app-crash.log',
  );

  static void recordSync(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    try {
      final File target = file;
      target.parent.createSync(recursive: true);
      if (target.existsSync() && target.lengthSync() >= maxBytes) {
        final File previous = File('${target.path}.previous');
        if (previous.existsSync()) previous.deleteSync();
        target.renameSync(previous.path);
      }
      final String entry = <String>[
        '--- ${DateTime.now().toUtc().toIso8601String()} $source ---',
        _redact('$error'),
        _redact('$stackTrace'),
        '',
      ].join('\n');
      target.writeAsStringSync(entry, mode: FileMode.append, flush: true);
    } on Object {
      // Crash reporting must never trigger another application failure.
    }
  }

  static String _redact(String value) => value.replaceAllMapped(
    RegExp(
      r'(authorization|api[_-]?key|access[_-]?token|password|secret)'
      r'\s*[:=]\s*[^\s,;}]+',
      caseSensitive: false,
    ),
    (Match match) => '${match.group(1)}=<redacted>',
  );
}
