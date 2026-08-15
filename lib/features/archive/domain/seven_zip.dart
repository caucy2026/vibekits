import 'dart:io';

/// 7z 格式支持，基于官方 7za 命令行（native/7za/7za.exe）。
class SevenZipEntry {
  const SevenZipEntry({
    required this.name,
    required this.size,
    required this.isDirectory,
  });

  final String name;
  final int size;
  final bool isDirectory;
}

/// 解压冲突策略 → 7za 参数。
String sevenZipOverwriteArg(String policy) {
  switch (policy) {
    case 'overwrite':
      return '-aoa';
    case 'skip':
      return '-aos';
    default:
      return '-aou';
  }
}

abstract final class SevenZip {
  static List<String> _candidatePaths() {
    final List<String> candidates = <String>[];
    final String? env = Platform.environment['VIBEKITS_7ZA'];
    if (env != null && env.isNotEmpty) {
      candidates.add(env);
    }
    candidates.add(
      '${Directory.current.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}7za${Platform.pathSeparator}7za.exe',
    );
    candidates.add(
      '${Platform.resolvedExecutable}${Platform.pathSeparator}..'
      '${Platform.pathSeparator}native${Platform.pathSeparator}7za'
      '${Platform.pathSeparator}7za.exe',
    );
    return candidates;
  }

  static String? findExecutable() {
    for (final String path in _candidatePaths()) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  static bool get isAvailable => findExecutable() != null;

  /// 列出 7z 压缩包条目。
  static Future<List<SevenZipEntry>> list(String archivePath) async {
    final String? exe = findExecutable();
    if (exe == null) {
      throw const FileSystemException('未找到 7za.exe');
    }
    final ProcessResult result = await Process.run(exe, <String>[
      'l',
      '-slt',
      archivePath,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('7z 列表失败：${result.stderr}');
    }
    return _parseList(result.stdout as String);
  }

  static List<SevenZipEntry> _parseList(String output) {
    final List<SevenZipEntry> entries = <SevenZipEntry>[];
    String? name;
    int size = 0;
    bool isDir = false;
    bool inEntry = false;

    void flush() {
      if (name != null) {
        entries.add(SevenZipEntry(name: name!, size: size, isDirectory: isDir));
      }
      name = null;
      size = 0;
      isDir = false;
    }

    for (final String line in output.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed == '--') {
        flush();
        inEntry = true;
        continue;
      }
      if (!inEntry) continue;
      if (trimmed.startsWith('Path = ')) {
        name = trimmed.substring('Path = '.length);
      } else if (trimmed.startsWith('Size = ')) {
        size = int.tryParse(trimmed.substring('Size = '.length)) ?? 0;
      } else if (trimmed.startsWith('Folder = ')) {
        isDir = trimmed.substring('Folder = '.length) == '+';
      }
    }
    flush();
    return entries;
  }

  /// 解压 7z 到目标目录。
  static Future<void> extract(
    String archivePath,
    String targetDir, {
    List<String>? selectedEntries,
    String policy = 'rename',
  }) async {
    final String? exe = findExecutable();
    if (exe == null) {
      throw const FileSystemException('未找到 7za.exe');
    }
    Directory(targetDir).createSync(recursive: true);
    final List<String> args = <String>['x', archivePath];
    if (selectedEntries != null && selectedEntries.isNotEmpty) {
      args.addAll(selectedEntries);
    }
    args.addAll(<String>['-o$targetDir', '-y', sevenZipOverwriteArg(policy)]);
    final ProcessResult result = await Process.run(exe, args);
    if (result.exitCode != 0) {
      throw FileSystemException('7z 解压失败：${result.stderr}');
    }
  }
}
