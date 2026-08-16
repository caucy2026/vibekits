import 'dart:io';

import 'archive_service.dart';
import 'disk_space.dart';
import 'atomic_file.dart';

/// Unified native archive support backed by official 7-Zip.
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

/// 解压冲突策略 → 7-Zip 参数。
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
    final String? env =
        Platform.environment['VIBEKITS_7Z'] ??
        Platform.environment['VIBEKITS_7ZA'];
    if (env != null && env.isNotEmpty) {
      candidates.add(env);
    }
    candidates.add(
      '${Directory.current.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}7zip${Platform.pathSeparator}7z.exe',
    );
    candidates.add(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}tools${Platform.pathSeparator}7zip'
      '${Platform.pathSeparator}7z.exe',
    );
    candidates.add(
      '${Directory.current.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}7za${Platform.pathSeparator}7za.exe',
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
  static Future<List<SevenZipEntry>> list(
    String archivePath, {
    int maxEntries = 100000,
    int maxSingleExpandedBytes = 20 * 1024 * 1024 * 1024,
  }) async {
    final String? exe = findExecutable();
    if (exe == null) {
      throw const FileSystemException('未找到 Vibekits 内置 7-Zip 后端');
    }
    final ProcessResult result = await Process.run(exe, <String>[
      'l',
      '-slt',
      archivePath,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('7z 列表失败：${result.stderr}');
    }
    final List<SevenZipEntry> entries = _parseList(result.stdout as String);
    if (entries.length > maxEntries) {
      throw FormatException('压缩包条目超过安全上限 $maxEntries');
    }
    for (final SevenZipEntry entry in entries) {
      if (entry.size < 0 || entry.size > maxSingleExpandedBytes) {
        throw FormatException('条目展开大小超过安全上限：${entry.name}');
      }
    }
    return entries;
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
      if (RegExp(r'^-{5,}$').hasMatch(trimmed)) {
        flush();
        inEntry = true;
        continue;
      }
      if (!inEntry) continue;
      if (trimmed.startsWith('Path = ')) {
        if (name != null) flush();
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

  /// 解压 7-Zip 后端支持的压缩包到目标目录。
  static Future<void> extract(
    String archivePath,
    String targetDir, {
    List<String>? selectedEntries,
    String policy = 'rename',
  }) async {
    final ExtractResult result = await extractCancellable(
      archivePath,
      targetDir,
      selectedEntries: selectedEntries,
      policy: policy,
    );
    if (result.failed > 0) {
      throw FileSystemException('7z 解压失败：${result.failures.join('；')}');
    }
  }

  static Future<ExtractResult> extractCancellable(
    String archivePath,
    String targetDir, {
    List<String>? selectedEntries,
    String policy = 'rename',
    ArchiveCancellationToken? cancellationToken,
    void Function(ArchiveExtractProgress progress)? onProgress,
    ArchiveConflictResolver? onConflict,
    int? Function(String path)? availableDiskBytes,
    int maxEntries = 100000,
    int maxSingleExpandedBytes = 20 * 1024 * 1024 * 1024,
    int maxTotalExpandedBytes = 50 * 1024 * 1024 * 1024,
    int maxCompressionRatio = 1000,
  }) async {
    final ArchiveCancellationToken token =
        cancellationToken ?? ArchiveCancellationToken();
    final String? exe = findExecutable();
    if (exe == null) {
      throw const FileSystemException('未找到 Vibekits 内置 7-Zip 后端');
    }
    final List<SevenZipEntry> listing = await list(
      archivePath,
      maxEntries: maxEntries,
      maxSingleExpandedBytes: maxSingleExpandedBytes,
    );
    final Set<String>? selected = selectedEntries?.toSet();
    final List<SevenZipEntry> plan = listing
        .where(
          (SevenZipEntry entry) =>
              !entry.isDirectory &&
              (selected == null || selected.contains(entry.name)),
        )
        .toList(growable: false);
    for (final SevenZipEntry entry in plan) {
      if (ArchiveService.safeRelativePath(entry.name) == null) {
        throw FormatException('7z 条目路径不安全：${entry.name}');
      }
    }
    if (token.isCancelled || (selected != null && plan.isEmpty)) {
      return ExtractResult(
        succeeded: 0,
        skipped: 0,
        failed: 0,
        failures: const <String>[],
        cancelled: token.isCancelled,
      );
    }
    final int totalBytes = plan.fold<int>(
      0,
      (int sum, SevenZipEntry entry) => sum + entry.size,
    );
    if (totalBytes > maxTotalExpandedBytes) {
      throw FormatException('选择内容的总展开大小超过安全上限');
    }
    final int archiveBytes = await File(archivePath).length();
    if (archiveBytes > 0 && totalBytes > archiveBytes * maxCompressionRatio) {
      throw FormatException('选择内容的展开比例超过安全上限');
    }
    final int? available = (availableDiskBytes ?? DiskSpace.availableBytes)(
      targetDir,
    );
    if (available != null && available < totalBytes) {
      throw FileSystemException(
        '目标磁盘空间不足：需要 $totalBytes 字节，可用 $available 字节',
        targetDir,
      );
    }
    final Directory target = Directory(targetDir);
    await target.create(recursive: true);
    final Directory staging = Directory(
      '${target.path}${Platform.pathSeparator}.vibekits-7z-${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create();
    final List<String> args = <String>['x', archivePath];
    if (plan.isNotEmpty) {
      args.addAll(plan.map((SevenZipEntry entry) => entry.name));
    }
    args.addAll(<String>['-o${staging.path}', '-y', '-aoa', '-bsp1']);
    final Process process = await Process.start(exe, args);
    final StringBuffer outputs = StringBuffer();
    final StringBuffer errors = StringBuffer();
    final Future<void> stdoutDone = process.stdout
        .transform(const SystemEncoding().decoder)
        .forEach((String chunk) {
          outputs.write(chunk);
          final Match? match = RegExp(r'(\d+)%').firstMatch(chunk);
          final int percent = int.tryParse(match?.group(1) ?? '') ?? 0;
          onProgress?.call(
            ArchiveExtractProgress(
              currentFile: '7z 解压进程',
              completedFiles: 0,
              totalFiles: plan.length,
              writtenBytes: totalBytes * percent ~/ 100,
              totalBytes: totalBytes,
            ),
          );
        });
    final Future<void> stderrDone = process.stderr
        .transform(const SystemEncoding().decoder)
        .forEach(errors.write);
    while (!token.isCancelled) {
      final bool exited = await Future.any(<Future<bool>>[
        process.exitCode.then((int _) => true),
        Future<bool>.delayed(const Duration(milliseconds: 50), () => false),
      ]);
      if (exited) break;
    }
    if (token.isCancelled) process.kill();
    final int exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;
    if (token.isCancelled) {
      await _deleteStaging(staging);
      return const ExtractResult(
        succeeded: 0,
        skipped: 0,
        failed: 0,
        failures: <String>[],
        cancelled: true,
      );
    }
    if (exitCode != 0) {
      await _deleteStaging(staging);
      throw FileSystemException(
        '7z 解压失败（退出码 $exitCode）：${errors.isEmpty ? outputs : errors}',
      );
    }

    int succeeded = 0;
    int skipped = 0;
    int failed = 0;
    int writtenBytes = 0;
    final List<String> failures = <String>[];
    for (final SevenZipEntry entry in plan) {
      if (token.isCancelled) break;
      final String safe = ArchiveService.safeRelativePath(entry.name)!;
      final File source = File('${staging.path}${Platform.pathSeparator}$safe');
      File destination = File('${target.path}${Platform.pathSeparator}$safe');
      try {
        if (!await source.exists()) {
          failed++;
          failures.add('${entry.name}（7z 未生成该文件）');
          continue;
        }
        await destination.parent.create(recursive: true);
        if (await destination.exists()) {
          String effectivePolicy = policy;
          if (policy == 'ask') {
            final ConflictPolicy decision =
                await onConflict?.call(destination.path) ?? ConflictPolicy.skip;
            effectivePolicy = decision.name;
          }
          if (effectivePolicy == 'skip') {
            skipped++;
            continue;
          }
          if (effectivePolicy == 'rename') {
            destination = _renameTarget(destination);
          }
        }
        await AtomicFile.commit(source, destination);
        succeeded++;
        writtenBytes += entry.size;
        onProgress?.call(
          ArchiveExtractProgress(
            currentFile: entry.name,
            completedFiles: succeeded,
            totalFiles: plan.length,
            writtenBytes: writtenBytes,
            totalBytes: totalBytes,
          ),
        );
      } catch (error) {
        failed++;
        failures.add('${entry.name}（$error）');
      }
    }
    await _deleteStaging(staging);
    return ExtractResult(
      succeeded: succeeded,
      skipped: skipped,
      failed: failed,
      failures: failures,
      cancelled: token.isCancelled,
      writtenBytes: writtenBytes,
    );
  }

  static File _renameTarget(File file) {
    final String directory = file.parent.path;
    final String name = file.uri.pathSegments.last;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String extension = dot > 0 ? name.substring(dot) : '';
    for (int index = 1; index < 10000; index++) {
      final File candidate = File(
        '$directory${Platform.pathSeparator}$stem ($index)$extension',
      );
      if (!candidate.existsSync()) return candidate;
    }
    throw const FileSystemException('无法生成无冲突文件名');
  }

  static Future<void> _deleteStaging(Directory staging) async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
