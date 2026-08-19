import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'tool_result.dart';

abstract final class CodeStatisticsService {
  static const int maxFiles = 50000;
  static const int maxFileBytes = 8 * 1024 * 1024;

  static Future<ToolResult> analyze(String input, {String extensions = ''}) =>
      Isolate.run<ToolResult>(
        () => _analyzeSync(input, extensions),
        debugName: 'vibekits-code-statistics',
      );

  static ToolResult _analyzeSync(String input, String extensions) {
    final String path = input.trim();
    if (path.isEmpty) return const ToolFailure('请输入项目目录或源码文件路径');
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory &&
        type != FileSystemEntityType.file) {
      return const ToolFailure('路径不存在或不是普通目录/文件');
    }
    final Set<String> filter = extensions
        .split(RegExp(r'[,;\s]+'))
        .map((String value) => value.trim().toLowerCase().replaceFirst('.', ''))
        .where((String value) => value.isNotEmpty)
        .toSet();
    final Iterable<FileSystemEntity> entities =
        type == FileSystemEntityType.file
        ? <FileSystemEntity>[File(path)]
        : Directory(path).listSync(recursive: true, followLinks: false);
    final Map<String, _LanguageCount> counts = <String, _LanguageCount>{};
    int visited = 0;
    int skipped = 0;
    bool truncated = false;
    for (final FileSystemEntity entity in entities) {
      if (entity is! File) continue;
      if (_isIgnored(entity.path)) continue;
      if (visited >= maxFiles) {
        truncated = true;
        break;
      }
      final String extension = _extension(entity.path);
      if (filter.isNotEmpty && !filter.contains(extension)) continue;
      final _Language? language = _languages[extension];
      if (language == null) continue;
      visited++;
      try {
        final int size = entity.lengthSync();
        if (size > maxFileBytes) {
          skipped++;
          continue;
        }
        final List<int> bytes = entity.readAsBytesSync();
        if (bytes.contains(0)) {
          skipped++;
          continue;
        }
        final String text = utf8.decode(bytes, allowMalformed: true);
        final _LanguageCount count = counts.putIfAbsent(
          language.name,
          () => _LanguageCount(language.name),
        );
        count.files++;
        count.bytes += size;
        _countLines(text, language, count);
      } on FileSystemException {
        skipped++;
      }
    }
    final List<_LanguageCount> sorted = counts.values.toList()
      ..sort((_LanguageCount a, _LanguageCount b) => b.code.compareTo(a.code));
    final int files = sorted.fold(
      0,
      (int sum, _LanguageCount item) => sum + item.files,
    );
    final int code = sorted.fold(
      0,
      (int sum, _LanguageCount item) => sum + item.code,
    );
    final int comments = sorted.fold(
      0,
      (int sum, _LanguageCount item) => sum + item.comments,
    );
    final int blanks = sorted.fold(
      0,
      (int sum, _LanguageCount item) => sum + item.blanks,
    );
    return ToolSuccess(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'root': File(path).absolute.path,
        'files': files,
        'codeLines': code,
        'commentLines': comments,
        'blankLines': blanks,
        'skippedFiles': skipped,
        'truncated': truncated,
        'languages': <Map<String, Object?>>[
          for (final _LanguageCount item in sorted) item.toJson(),
        ],
      }),
    );
  }

  static void _countLines(
    String text,
    _Language language,
    _LanguageCount count,
  ) {
    bool inBlock = false;
    final List<String> lines = text.replaceAll('\r\n', '\n').split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    for (final String source in lines) {
      String line = source.trim();
      if (line.isEmpty) {
        count.blanks++;
        continue;
      }
      if (inBlock) {
        count.comments++;
        final int end = line.indexOf(language.blockEnd);
        if (end >= 0) {
          inBlock = false;
          line = line.substring(end + language.blockEnd.length).trim();
          if (line.isNotEmpty) count.code++;
        }
        continue;
      }
      if (language.blockStart.isNotEmpty &&
          line.startsWith(language.blockStart)) {
        count.comments++;
        if (!line.contains(language.blockEnd, language.blockStart.length)) {
          inBlock = true;
        }
      } else if (language.lineComments.any(line.startsWith)) {
        count.comments++;
      } else {
        count.code++;
      }
    }
  }

  static bool _isIgnored(String path) {
    final List<String> parts = path
        .replaceAll('\\', '/')
        .split('/')
        .map((String value) => value.toLowerCase())
        .toList();
    return parts.any(_ignoredDirectories.contains);
  }

  static String _extension(String path) {
    final String name = path.replaceAll('\\', '/').split('/').last;
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? name.toLowerCase() : name.substring(dot + 1).toLowerCase();
  }
}

class _Language {
  const _Language(
    this.name, {
    this.lineComments = const <String>['//'],
    this.blockStart = '/*',
    this.blockEnd = '*/',
  });

  final String name;
  final List<String> lineComments;
  final String blockStart;
  final String blockEnd;
}

class _LanguageCount {
  _LanguageCount(this.name);

  final String name;
  int files = 0;
  int code = 0;
  int comments = 0;
  int blanks = 0;
  int bytes = 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'language': name,
    'files': files,
    'code': code,
    'comments': comments,
    'blanks': blanks,
    'bytes': bytes,
  };
}

const Set<String> _ignoredDirectories = <String>{
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'node_modules',
  'vendor',
  'build',
  'dist',
  'target',
  'coverage',
  '__pycache__',
};

const Map<String, _Language> _languages = <String, _Language>{
  'dart': _Language('Dart'),
  'js': _Language('JavaScript'),
  'jsx': _Language('JavaScript'),
  'ts': _Language('TypeScript'),
  'tsx': _Language('TypeScript'),
  'java': _Language('Java'),
  'kt': _Language('Kotlin'),
  'kts': _Language('Kotlin'),
  'c': _Language('C'),
  'h': _Language('C/C++'),
  'cc': _Language('C/C++'),
  'cpp': _Language('C/C++'),
  'cs': _Language('C#'),
  'swift': _Language('Swift'),
  'go': _Language('Go'),
  'rs': _Language('Rust'),
  'php': _Language('PHP'),
  'py': _Language(
    'Python',
    lineComments: <String>['#'],
    blockStart: '',
    blockEnd: '',
  ),
  'rb': _Language(
    'Ruby',
    lineComments: <String>['#'],
    blockStart: '',
    blockEnd: '',
  ),
  'sh': _Language(
    'Shell',
    lineComments: <String>['#'],
    blockStart: '',
    blockEnd: '',
  ),
  'ps1': _Language('PowerShell', lineComments: <String>['#']),
  'sql': _Language('SQL', lineComments: <String>['--']),
  'html': _Language(
    'HTML',
    lineComments: <String>[],
    blockStart: '<!--',
    blockEnd: '-->',
  ),
  'css': _Language('CSS', lineComments: <String>[]),
  'vue': _Language('Vue'),
  'svelte': _Language('Svelte'),
  'yaml': _Language(
    'YAML',
    lineComments: <String>['#'],
    blockStart: '',
    blockEnd: '',
  ),
  'yml': _Language(
    'YAML',
    lineComments: <String>['#'],
    blockStart: '',
    blockEnd: '',
  ),
  'toml': _Language(
    'TOML',
    lineComments: <String>['#'],
    blockStart: '',
    blockEnd: '',
  ),
};
