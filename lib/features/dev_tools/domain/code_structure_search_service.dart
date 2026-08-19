import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'tool_result.dart';

abstract final class CodeStructureSearchService {
  static Future<ToolResult> search(String root, String params) =>
      Isolate.run<ToolResult>(
        () => _searchSync(root, params),
        debugName: 'vibekits-code-structure-search',
      );

  static ToolResult _searchSync(String root, String params) {
    final String path = root.trim();
    if (path.isEmpty) return const ToolFailure('请输入项目目录或源码文件路径');
    final List<String> parts = params.split('|');
    final String kind = parts.length > 1
        ? parts.first.trim().toLowerCase()
        : 'any';
    final String query =
        (parts.length > 1 ? parts.sublist(1).join('|') : params).trim();
    if (query.isEmpty) return const ToolFailure('请输入符号名称，例如 class|UserService');
    if (!const <String>{'any', 'class', 'function', 'type'}.contains(kind)) {
      return const ToolFailure('类型只能是 any/class/function/type');
    }
    final FileSystemEntityType rootType = FileSystemEntity.typeSync(
      path,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.file &&
        rootType != FileSystemEntityType.directory) {
      return const ToolFailure('路径不存在或不可访问');
    }
    final Iterable<FileSystemEntity> entities =
        rootType == FileSystemEntityType.file
        ? <FileSystemEntity>[File(path)]
        : Directory(path).listSync(recursive: true, followLinks: false);
    final bool caseSensitive = query.toLowerCase() != query;
    final String needle = caseSensitive ? query : query.toLowerCase();
    final List<Map<String, Object?>> matches = <Map<String, Object?>>[];
    int visited = 0;
    int skipped = 0;
    bool truncated = false;
    for (final FileSystemEntity entity in entities) {
      if (entity is! File || _ignored(entity.path)) continue;
      final String extension = _extension(entity.path);
      final List<_DeclarationPattern>? patterns = _patterns[extension];
      if (patterns == null) continue;
      if (visited++ >= 50000 || matches.length >= 500) {
        truncated = true;
        break;
      }
      try {
        if (entity.lengthSync() > 8 * 1024 * 1024) {
          skipped++;
          continue;
        }
        final List<String> lines = entity.readAsLinesSync();
        bool inBlockComment = false;
        for (int index = 0; index < lines.length; index++) {
          String line = lines[index].trim();
          if (inBlockComment) {
            if (line.contains('*/')) inBlockComment = false;
            continue;
          }
          if (line.startsWith('/*')) {
            if (!line.contains('*/', 2)) inBlockComment = true;
            continue;
          }
          if (line.startsWith('//') || line.startsWith('#')) continue;
          for (final _DeclarationPattern pattern in patterns) {
            if (kind != 'any' && kind != pattern.kind) continue;
            final RegExpMatch? found = pattern.expression.firstMatch(line);
            if (found == null) continue;
            final String name = found.namedGroup('name') ?? '';
            final String comparable = caseSensitive ? name : name.toLowerCase();
            if (!comparable.contains(needle)) continue;
            matches.add(<String, Object?>{
              'path': entity.absolute.path,
              'line': index + 1,
              'kind': pattern.kind,
              'name': name,
              'declaration': line.length <= 240
                  ? line
                  : '${line.substring(0, 237)}…',
            });
            break;
          }
          if (matches.length >= 500) {
            truncated = true;
            break;
          }
        }
      } on FileSystemException {
        skipped++;
      }
      if (truncated) break;
    }
    return ToolSuccess(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'root': File(path).absolute.path,
        'query': query,
        'kind': kind,
        'visitedFiles': visited,
        'skippedFiles': skipped,
        'truncated': truncated,
        'matches': matches,
      }),
    );
  }

  static bool _ignored(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .map((String value) => value.toLowerCase())
      .any(
        const <String>{
          '.git',
          '.dart_tool',
          'node_modules',
          'vendor',
          'build',
          'dist',
          'target',
          'coverage',
          '__pycache__',
        }.contains,
      );

  static String _extension(String path) {
    final String name = path.replaceAll('\\', '/').split('/').last;
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

class _DeclarationPattern {
  const _DeclarationPattern(this.kind, this.expression);
  final String kind;
  final RegExp expression;
}

final Map<String, List<_DeclarationPattern>>
_patterns = <String, List<_DeclarationPattern>>{
  for (final String extension in <String>['dart', 'java', 'kt', 'swift', 'cs'])
    extension: <_DeclarationPattern>[
      _DeclarationPattern(
        'class',
        RegExp(
          r'\b(?:class|interface|enum|mixin|record)\s+(?<name>[A-Za-z_]\w*)',
        ),
      ),
      _DeclarationPattern(
        'function',
        RegExp(r'\b(?<name>[A-Za-z_]\w*)\s*\([^;]*\)\s*(?:async\s*)?[{=>]'),
      ),
    ],
  for (final String extension in <String>['js', 'jsx', 'ts', 'tsx'])
    extension: <_DeclarationPattern>[
      _DeclarationPattern(
        'class',
        RegExp(r'\b(?:class|interface|enum|type)\s+(?<name>[A-Za-z_$][\w$]*)'),
      ),
      _DeclarationPattern(
        'function',
        RegExp(r'\bfunction\s+(?<name>[A-Za-z_$][\w$]*)\s*\('),
      ),
      _DeclarationPattern(
        'function',
        RegExp(
          r'\b(?:const|let|var)\s+(?<name>[A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>',
        ),
      ),
    ],
  for (final String extension in <String>['py', 'rb'])
    extension: <_DeclarationPattern>[
      _DeclarationPattern('class', RegExp(r'^class\s+(?<name>[A-Za-z_]\w*)')),
      _DeclarationPattern(
        'function',
        RegExp(r'^(?:async\s+)?def\s+(?<name>[A-Za-z_]\w*)\s*\('),
      ),
    ],
  'go': <_DeclarationPattern>[
    _DeclarationPattern('type', RegExp(r'^type\s+(?<name>[A-Za-z_]\w*)\s+')),
    _DeclarationPattern(
      'function',
      RegExp(r'^func\s+(?:\([^)]*\)\s*)?(?<name>[A-Za-z_]\w*)\s*\('),
    ),
  ],
  'rs': <_DeclarationPattern>[
    _DeclarationPattern(
      'type',
      RegExp(r'\b(?:struct|enum|trait|type)\s+(?<name>[A-Za-z_]\w*)'),
    ),
    _DeclarationPattern(
      'function',
      RegExp(r'\bfn\s+(?<name>[A-Za-z_]\w*)\s*\('),
    ),
  ],
  for (final String extension in <String>['c', 'h', 'cc', 'cpp'])
    extension: <_DeclarationPattern>[
      _DeclarationPattern(
        'class',
        RegExp(r'\b(?:class|struct|enum)\s+(?<name>[A-Za-z_]\w*)'),
      ),
      _DeclarationPattern(
        'function',
        RegExp(r'\b(?<name>[A-Za-z_]\w*)\s*\([^;]*\)\s*\{'),
      ),
    ],
};
