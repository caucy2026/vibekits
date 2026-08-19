import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum FileSearchMode {
  name('文件名'),
  content('文件内容');

  const FileSearchMode(this.label);

  final String label;
}

class FileSearchRequest {
  const FileSearchRequest({
    required this.root,
    required this.query,
    this.mode = FileSearchMode.name,
    this.recursive = true,
    this.includeHidden = false,
    this.respectGitIgnore = true,
    this.smartCase = true,
    this.extensions = const <String>{},
    this.minimumBytes = 0,
    this.modifiedAfter,
    this.maxResults = 500,
    this.maxContentFileBytes = 8 * 1024 * 1024,
  });

  final String root;
  final String query;
  final FileSearchMode mode;
  final bool recursive;
  final bool includeHidden;
  final bool respectGitIgnore;
  final bool smartCase;
  final Set<String> extensions;
  final int minimumBytes;
  final DateTime? modifiedAfter;
  final int maxResults;
  final int maxContentFileBytes;

  void validate() {
    if (root.trim().isEmpty) throw const FormatException('请先选择搜索文件夹');
    if (query.trim().isEmpty) throw const FormatException('请输入搜索关键词');
    if (maxResults < 1 || maxResults > 5000) {
      throw const FormatException('结果上限必须在 1～5000 之间');
    }
    if (maxContentFileBytes < 1) {
      throw const FormatException('内容搜索文件上限必须大于 0');
    }
    if (minimumBytes < 0) throw const FormatException('最小文件大小不能为负数');
  }
}

class FileSearchCancellation {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final void Function() listener in List<void Function()>.of(
      _listeners,
    )) {
      listener();
    }
  }

  void addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeCancelListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

class FileSearchProgress {
  const FileSearchProgress({
    required this.currentPath,
    required this.visitedFiles,
    required this.matchedFiles,
    required this.skippedFiles,
  });

  final String currentPath;
  final int visitedFiles;
  final int matchedFiles;
  final int skippedFiles;
}

class FileSearchMatch {
  const FileSearchMatch({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    this.lineNumber,
    this.snippet,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final int? lineNumber;
  final String? snippet;
}

class FileSearchResult {
  const FileSearchResult({
    required this.matches,
    required this.cancelled,
    required this.truncated,
    required this.visitedFiles,
    required this.skippedFiles,
    required this.elapsed,
  });

  final List<FileSearchMatch> matches;
  final bool cancelled;
  final bool truncated;
  final int visitedFiles;
  final int skippedFiles;
  final Duration elapsed;
}

typedef FileSearchProgressCallback = void Function(FileSearchProgress progress);

/// 有界、可取消的文件搜索。
///
/// 不跟随符号链接；内容模式只读取不超过请求上限且不像二进制的文件，
/// 避免一次搜索吞掉大量内存或越过用户选择的目录。
abstract final class FileSearchService {
  static Future<FileSearchResult> search(
    FileSearchRequest request, {
    FileSearchCancellation? cancellation,
    FileSearchProgressCallback? onProgress,
  }) async {
    request.validate();
    final Stopwatch clock = Stopwatch()..start();
    final FileSearchCancellation token =
        cancellation ?? FileSearchCancellation();
    final String rootPath = request.root.trim();
    final FileSystemEntityType rootType = FileSystemEntity.typeSync(
      rootPath,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory) {
      throw const FileSystemException('搜索文件夹不存在或不可访问');
    }

    final String rawNeedle = request.query.trim();
    final bool caseSensitive =
        request.smartCase && rawNeedle.toLowerCase() != rawNeedle;
    final String needle = caseSensitive ? rawNeedle : rawNeedle.toLowerCase();
    final _GitIgnoreMatcher ignore = request.respectGitIgnore
        ? await _GitIgnoreMatcher.load(rootPath)
        : const _GitIgnoreMatcher(<_IgnoreRule>[]);
    final List<FileSearchMatch> matches = <FileSearchMatch>[];
    final List<Directory> pending = <Directory>[Directory(rootPath)];
    int visitedFiles = 0;
    int skippedFiles = 0;
    bool truncated = false;

    searchLoop:
    while (pending.isNotEmpty && !token.isCancelled) {
      final Directory directory = pending.removeLast();
      try {
        await for (final FileSystemEntity entity in directory.list(
          followLinks: false,
        )) {
          if (token.isCancelled) break searchLoop;
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          final String relative = _relativePath(rootPath, entity.path);
          if (ignore.ignores(
            relative,
            directory: type == FileSystemEntityType.directory,
          )) {
            continue;
          }
          if (type == FileSystemEntityType.directory) {
            if (request.recursive &&
                (request.includeHidden || !_isHidden(entity.path)) &&
                !_isSystemMetadataDirectory(entity.path)) {
              pending.add(Directory(entity.path));
            }
            continue;
          }
          if (type != FileSystemEntityType.file) continue;
          if (!request.includeHidden && _isHidden(entity.path)) continue;

          visitedFiles++;
          try {
            final File file = File(entity.path);
            final FileStat stat = await file.stat();
            if (stat.size < request.minimumBytes ||
                (request.modifiedAfter != null &&
                    stat.modified.isBefore(request.modifiedAfter!)) ||
                !_matchesExtension(entity.path, request.extensions)) {
              onProgress?.call(
                FileSearchProgress(
                  currentPath: entity.path,
                  visitedFiles: visitedFiles,
                  matchedFiles: matches.length,
                  skippedFiles: skippedFiles,
                ),
              );
              continue;
            }
            FileSearchMatch? match;
            if (request.mode == FileSearchMode.name) {
              final String name = _basename(entity.path);
              final String comparable = caseSensitive
                  ? name
                  : name.toLowerCase();
              if (comparable.contains(needle)) {
                match = FileSearchMatch(
                  path: entity.path,
                  name: name,
                  size: stat.size,
                  modified: stat.modified,
                );
              }
            } else if (stat.size <= request.maxContentFileBytes) {
              match = await _searchContent(
                file,
                stat,
                needle,
                caseSensitive,
                token,
              );
            } else {
              skippedFiles++;
            }
            if (match != null) matches.add(match);
          } on FileSystemException {
            skippedFiles++;
          }

          onProgress?.call(
            FileSearchProgress(
              currentPath: entity.path,
              visitedFiles: visitedFiles,
              matchedFiles: matches.length,
              skippedFiles: skippedFiles,
            ),
          );
          if (matches.length >= request.maxResults) {
            truncated = true;
            break searchLoop;
          }
          if (visitedFiles % 25 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      } on FileSystemException {
        skippedFiles++;
      }
    }

    clock.stop();
    matches.sort(
      (FileSearchMatch left, FileSearchMatch right) =>
          left.path.toLowerCase().compareTo(right.path.toLowerCase()),
    );
    return FileSearchResult(
      matches: List<FileSearchMatch>.unmodifiable(matches),
      cancelled: token.isCancelled,
      truncated: truncated,
      visitedFiles: visitedFiles,
      skippedFiles: skippedFiles,
      elapsed: clock.elapsed,
    );
  }

  static Future<FileSearchMatch?> _searchContent(
    File file,
    FileStat stat,
    String needle,
    bool caseSensitive,
    FileSearchCancellation token,
  ) async {
    final List<int> bytes = await file.readAsBytes();
    if (token.isCancelled || _looksBinary(bytes)) return null;
    final String text = utf8.decode(bytes, allowMalformed: true);
    final int offset = (caseSensitive ? text : text.toLowerCase()).indexOf(
      needle,
    );
    if (offset < 0) return null;
    final int lineStart = offset == 0
        ? 0
        : text.lastIndexOf('\n', offset - 1) + 1;
    final int nextBreak = text.indexOf('\n', offset);
    final int lineEnd = nextBreak < 0 ? text.length : nextBreak;
    final int lineNumber =
        1 + '\n'.allMatches(text.substring(0, offset)).length;
    String snippet = text.substring(lineStart, lineEnd).trim();
    if (snippet.length > 240) snippet = '${snippet.substring(0, 237)}…';
    return FileSearchMatch(
      path: file.path,
      name: _basename(file.path),
      size: stat.size,
      modified: stat.modified,
      lineNumber: lineNumber,
      snippet: snippet,
    );
  }

  static bool _looksBinary(List<int> bytes) {
    final int probeLength = bytes.length.clamp(0, 4096);
    for (int index = 0; index < probeLength; index++) {
      if (bytes[index] == 0) return true;
    }
    return false;
  }

  static bool _isHidden(String path) => _basename(path).startsWith('.');

  static bool _matchesExtension(String path, Set<String> extensions) {
    if (extensions.isEmpty) return true;
    final String name = _basename(path).toLowerCase();
    final int dot = name.lastIndexOf('.');
    final String extension = dot < 0 ? '' : name.substring(dot + 1);
    return extensions.contains(extension);
  }

  static bool _isSystemMetadataDirectory(String path) {
    final String name = _basename(path).toLowerCase();
    return name == r'$recycle.bin' || name == 'system volume information';
  }

  static String _basename(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .where((String part) => part.isNotEmpty)
      .last;

  static String _relativePath(String root, String path) {
    final String normalizedRoot = Directory(root).absolute.path
        .replaceAll('\\', '/');
    final String normalizedPath = File(path).absolute.path
        .replaceAll('\\', '/');
    if (normalizedPath.toLowerCase().startsWith(normalizedRoot.toLowerCase())) {
      return normalizedPath
          .substring(normalizedRoot.length)
          .replaceFirst(RegExp(r'^/+'), '');
    }
    return normalizedPath;
  }
}

class _GitIgnoreMatcher {
  const _GitIgnoreMatcher(this.rules);

  final List<_IgnoreRule> rules;

  static Future<_GitIgnoreMatcher> load(String root) async {
    final File file = File(
      '${Directory(root).absolute.path}${Platform.pathSeparator}.gitignore',
    );
    if (!await file.exists()) return const _GitIgnoreMatcher(<_IgnoreRule>[]);
    try {
      final List<_IgnoreRule> rules = <_IgnoreRule>[];
      for (String line in await file.readAsLines()) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        bool negated = false;
        if (line.startsWith('!')) {
          negated = true;
          line = line.substring(1);
        }
        if (line.isEmpty) continue;
        rules.add(_IgnoreRule.fromPattern(line, negated));
        if (rules.length >= 2000) break;
      }
      return _GitIgnoreMatcher(List<_IgnoreRule>.unmodifiable(rules));
    } on Object {
      return const _GitIgnoreMatcher(<_IgnoreRule>[]);
    }
  }

  bool ignores(String relative, {required bool directory}) {
    final String path = relative.replaceAll('\\', '/');
    bool ignored = false;
    for (final _IgnoreRule rule in rules) {
      if (rule.matches(path, directory: directory)) ignored = !rule.negated;
    }
    return ignored;
  }
}

class _IgnoreRule {
  const _IgnoreRule(this.expression, this.negated, this.directoryOnly);

  factory _IgnoreRule.fromPattern(String pattern, bool negated) {
    bool directoryOnly = pattern.endsWith('/');
    String value = pattern.replaceFirst(RegExp(r'^/+'), '');
    if (directoryOnly) value = value.substring(0, value.length - 1);
    final bool anyDepth = !value.contains('/');
    final StringBuffer regex = StringBuffer(anyDepth ? r'(^|.*/)' : '^');
    for (int index = 0; index < value.length; index++) {
      final String char = value[index];
      if (char == '*') {
        if (index + 1 < value.length && value[index + 1] == '*') {
          regex.write('.*');
          index++;
        } else {
          regex.write('[^/]*');
        }
      } else if (char == '?') {
        regex.write('[^/]');
      } else {
        regex.write(RegExp.escape(char));
      }
    }
    regex.write(directoryOnly ? r'(/.*)?$' : r'$');
    return _IgnoreRule(RegExp(regex.toString()), negated, directoryOnly);
  }

  final RegExp expression;
  final bool negated;
  final bool directoryOnly;

  bool matches(String path, {required bool directory}) =>
      (!directoryOnly || directory) && expression.hasMatch(path);
}
