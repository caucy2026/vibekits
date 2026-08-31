import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/platform_storage_layout.dart';

class HarnessRuntimeLogEntry {
  const HarnessRuntimeLogEntry({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
}

/// Persistent, redacted diagnostics shared by the Harness UI and its tools.
abstract final class HarnessRuntimeLogStore {
  static String _rootPath = '';
  static Future<void> _writeQueue = Future<void>.value();

  static String get rootPath => _rootPath.trim().isEmpty
      ? PlatformStorageLayout.current().harnessDebugDirectory
      : _rootPath;

  static void configure(String rootPath) {
    final String normalized = rootPath.trim();
    if (normalized.isNotEmpty && Directory(normalized).isAbsolute) {
      _rootPath = normalized;
    }
  }

  static Future<void> appendWorkEvent(Map<String, Object?> event) {
    final Map<String, Object?> safe = _redactMap(event);
    _writeQueue = _writeQueue
        .then((_) async {
          final Directory logs = Directory(
            '$rootPath${Platform.pathSeparator}logs',
          );
          await logs.create(recursive: true);
          final File file = File(
            '${logs.path}${Platform.pathSeparator}harness-work.jsonl',
          );
          await file.writeAsString(
            '${jsonEncode(safe)}\n',
            mode: FileMode.append,
            flush: false,
          );
        })
        .catchError((Object _) {
          // Logging must never break the task it observes.
        });
    return _writeQueue;
  }

  static Future<List<HarnessRuntimeLogEntry>> listLogs() async {
    final Directory logs = Directory('$rootPath${Platform.pathSeparator}logs');
    if (!await logs.exists()) return const <HarnessRuntimeLogEntry>[];
    final List<HarnessRuntimeLogEntry> result = <HarnessRuntimeLogEntry>[];
    await for (final FileSystemEntity entity in logs.list(followLinks: false)) {
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.log') &&
              !entity.path.toLowerCase().endsWith('.jsonl')) {
        continue;
      }
      try {
        final FileStat stat = await entity.stat();
        result.add(
          HarnessRuntimeLogEntry(
            path: entity.path,
            name: _fileName(entity.path),
            size: stat.size,
            modified: stat.modified,
          ),
        );
      } on FileSystemException {
        // Keep other readable logs visible.
      }
    }
    result.sort(
      (HarnessRuntimeLogEntry left, HarnessRuntimeLogEntry right) =>
          right.modified.compareTo(left.modified),
    );
    return result;
  }

  static Future<String> readTail(
    String path, {
    int maxBytes = 256 * 1024,
  }) async {
    final String logsRoot = Directory(
      '$rootPath${Platform.pathSeparator}logs',
    ).absolute.path.toLowerCase();
    final File file = File(path).absolute;
    if (!file.path.toLowerCase().startsWith(
      '$logsRoot${Platform.pathSeparator}',
    )) {
      throw const FileSystemException('日志路径超出 Harness 日志目录');
    }
    final RandomAccessFile reader = await file.open();
    try {
      final int length = await reader.length();
      final int start = length > maxBytes ? length - maxBytes : 0;
      await reader.setPosition(start);
      final List<int> bytes = await reader.read(length - start);
      String text = const Utf8Decoder().convert(bytes);
      if (start > 0) {
        final int firstLine = text.indexOf('\n');
        if (firstLine >= 0) text = text.substring(firstLine + 1);
        text = '…已省略较早日志…\n$text';
      }
      return _redactText(text);
    } finally {
      await reader.close();
    }
  }

  static Map<String, Object?> _redactMap(Map<String, Object?> value) =>
      value.map((String key, Object? item) {
        final String lower = key.toLowerCase();
        if (lower.contains('password') ||
            lower.contains('secret') ||
            lower.contains('token') ||
            lower.contains('apikey') ||
            lower.contains('api_key')) {
          return MapEntry<String, Object?>(key, '<hidden>');
        }
        return MapEntry<String, Object?>(
          key,
          item is String ? _redactText(item) : item,
        );
      });

  static String _redactText(String value) => value
      .replaceAll(
        RegExp(
          r'(password|secret|token|api[_ -]?key)\s*[:=]\s*\S+',
          caseSensitive: false,
        ),
        r'$1=<hidden>',
      )
      .replaceAll(
        RegExp(r'authorization:\s*\S+', caseSensitive: false),
        'authorization: <hidden>',
      );

  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;
}
