import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 支持的压缩格式（7z/rar/iso 需原生 libarchive 层，纯 Dart 暂不支持）。
enum ArchiveFormat {
  zip,
  tar,
  gzip,
  bzip2,
  xz,
  sevenZip,
  rar,
  iso,
  unsupported,
}

ArchiveFormat archiveFormatForPath(String path) {
  final String lower = path.toLowerCase();
  if (lower.endsWith('.7z')) {
    return ArchiveFormat.sevenZip;
  }
  if (lower.endsWith('.rar')) {
    return ArchiveFormat.rar;
  }
  if (lower.endsWith('.iso')) {
    return ArchiveFormat.iso;
  }
  if (lower.endsWith('.zip')) {
    return ArchiveFormat.zip;
  }
  if (lower.endsWith('.tar')) {
    return ArchiveFormat.tar;
  }
  if (lower.endsWith('.tgz') || lower.endsWith('.tar.gz')) {
    return ArchiveFormat.tar;
  }
  if (lower.endsWith('.tbz2') || lower.endsWith('.tar.bz2')) {
    return ArchiveFormat.tar;
  }
  if (lower.endsWith('.txz') || lower.endsWith('.tar.xz')) {
    return ArchiveFormat.tar;
  }
  if (lower.endsWith('.gz')) {
    return ArchiveFormat.gzip;
  }
  if (lower.endsWith('.bz2')) {
    return ArchiveFormat.bzip2;
  }
  if (lower.endsWith('.xz')) {
    return ArchiveFormat.xz;
  }
  return ArchiveFormat.unsupported;
}

/// 压缩包条目（仅保留安全字段）。
class ArchiveEntry {
  const ArchiveEntry({
    required this.name,
    required this.isDirectory,
    required this.isSymlink,
    required this.symlinkTarget,
    required this.size,
    required this.file,
  });

  final String name;
  final bool isDirectory;
  final bool isSymlink;
  final String symlinkTarget;
  final int size;
  final ArchiveFile file;
}

/// 列表结果。
class ArchiveListing {
  const ArchiveListing({
    required this.format,
    required this.entries,
    required this.totalUncompressedSize,
    required this.sizeKnown,
  });

  final ArchiveFormat format;
  final List<ArchiveEntry> entries;
  final int totalUncompressedSize;
  final bool sizeKnown;
}

/// 冲突处理策略（docs/00 §3.2，ARC-004）。
enum ConflictPolicy { overwrite, skip, rename }

/// 解压结果。
class ExtractResult {
  const ExtractResult({
    required this.succeeded,
    required this.skipped,
    required this.failed,
    required this.failures,
  });

  final int succeeded;
  final int skipped;
  final int failed;
  final List<String> failures;
}

/// 解压缩服务（纯 Dart，基于 archive 包）。
abstract final class ArchiveService {
  static const int _maxEntries = 100000;
  static const int _maxSingleExpanded = 20 * 1024 * 1024 * 1024; // 20GiB

  /// 列出压缩包条目。
  static ArchiveListing list(Uint8List bytes, String path) {
    final ArchiveFormat format = archiveFormatForPath(path);
    if (format == ArchiveFormat.sevenZip ||
        format == ArchiveFormat.rar ||
        format == ArchiveFormat.iso ||
        format == ArchiveFormat.unsupported) {
      throw UnsupportedError('暂不支持该格式：$path');
    }

    final Archive archive = _decode(bytes, path, format);
    final List<ArchiveEntry> entries = <ArchiveEntry>[];
    int total = 0;
    bool sizeKnown = true;
    for (final ArchiveFile file in archive.files) {
      if (entries.length >= _maxEntries) {
        throw const FormatException('压缩包条目过多');
      }
      final String? safe = safeRelativePath(file.name);
      final String name = safe ?? file.name;
      final bool isSymlink = file.isSymbolicLink;
      final int size = file.size;
      if (!isSymlink && !file.isDirectory) {
        if (size < 0 || size > _maxSingleExpanded) {
          throw const FormatException('单文件展开大小超限');
        }
        total += size;
      }
      entries.add(
        ArchiveEntry(
          name: name,
          isDirectory: file.isDirectory,
          isSymlink: isSymlink,
          symlinkTarget: file.symbolicLink ?? '',
          size: size,
          file: file,
        ),
      );
    }
    return ArchiveListing(
      format: format,
      entries: entries,
      totalUncompressedSize: total,
      sizeKnown: sizeKnown,
    );
  }

  static Archive _decode(Uint8List bytes, String path, ArchiveFormat format) {
    switch (format) {
      case ArchiveFormat.zip:
        return ZipDecoder().decodeBytes(bytes);
      case ArchiveFormat.tar:
        return TarDecoder().decodeBytes(bytes);
      case ArchiveFormat.gzip:
        final Uint8List raw = GZipDecoder().decodeBytes(bytes);
        final String name = _singleName(path);
        return _singleEntryArchive(name, raw);
      case ArchiveFormat.bzip2:
        final Uint8List raw = BZip2Decoder().decodeBytes(bytes);
        return _singleEntryArchive(_singleName(path), raw);
      case ArchiveFormat.xz:
        final Uint8List raw = XZDecoder().decodeBytes(bytes);
        return _singleEntryArchive(_singleName(path), raw);
      case ArchiveFormat.sevenZip:
      case ArchiveFormat.rar:
      case ArchiveFormat.iso:
      case ArchiveFormat.unsupported:
        throw UnsupportedError('暂不支持该格式');
    }
  }

  static Archive _singleEntryArchive(String name, Uint8List raw) {
    return Archive()..addFile(ArchiveFile.bytes(name, raw));
  }

  static String _singleName(String path) {
    final int sep = path.lastIndexOf(Platform.pathSeparator);
    final String base = sep >= 0 ? path.substring(sep + 1) : path;
    if (base.endsWith('.tar.gz')) return base.substring(0, base.length - 8);
    if (base.endsWith('.tar.bz2')) return base.substring(0, base.length - 8);
    if (base.endsWith('.tar.xz')) return base.substring(0, base.length - 7);
    if (base.endsWith('.tgz')) return base.substring(0, base.length - 4);
    if (base.endsWith('.gz') || base.endsWith('.bz2') || base.endsWith('.xz')) {
      return base.substring(0, base.length - 3);
    }
    return base;
  }

  /// 规范化相对路径；不安全（绝对路径/盘符/`..`）返回 null。
  static String? safeRelativePath(String name) {
    String path = name.replaceAll('\\', '/');
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(path)) {
      return null;
    }
    final List<String> out = <String>[];
    for (final String part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') return null;
      out.add(part);
    }
    return out.isEmpty ? null : out.join('/');
  }

  /// 解压所选条目（空选择 = 全部）。
  static ExtractResult extract({
    required ArchiveListing listing,
    required String targetDir,
    required Set<String> selectedNames,
    ConflictPolicy policy = ConflictPolicy.rename,
  }) {
    int succeeded = 0;
    int skipped = 0;
    int failed = 0;
    final List<String> failures = <String>[];
    final Directory root = Directory(targetDir);

    for (final ArchiveEntry entry in listing.entries) {
      if (entry.isDirectory) continue;
      if (entry.isSymlink) {
        failed++;
        failures.add('${entry.name}（符号链接已跳过）');
        continue;
      }
      if (selectedNames.isNotEmpty && !selectedNames.contains(entry.name)) {
        continue;
      }
      final String? safe = safeRelativePath(entry.name);
      if (safe == null) {
        failed++;
        failures.add('${entry.name}（路径不安全，已拒绝）');
        continue;
      }
      final File out = File('${root.path}${Platform.pathSeparator}$safe');
      try {
        out.parent.createSync(recursive: true);
        if (out.existsSync()) {
          switch (policy) {
            case ConflictPolicy.overwrite:
              break;
            case ConflictPolicy.skip:
              skipped++;
              continue;
            case ConflictPolicy.rename:
              final File renamed = _renameTarget(out);
              _write(renamed, entry.file.content);
              break;
          }
        }
        if (!out.existsSync() || policy == ConflictPolicy.overwrite) {
          _write(out, entry.file.content);
        }
        succeeded++;
      } catch (e) {
        failed++;
        failures.add('$safe（$e）');
      }
    }
    return ExtractResult(
      succeeded: succeeded,
      skipped: skipped,
      failed: failed,
      failures: failures,
    );
  }

  static void _write(File file, Uint8List bytes) {
    file.writeAsBytesSync(bytes, flush: true);
  }

  static File _renameTarget(File file) {
    final String dir = file.parent.path;
    final String name = file.uri.pathSegments.last;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    for (int index = 1; index < 10000; index++) {
      final File candidate = File(
        '$dir${Platform.pathSeparator}$stem ($index)$ext',
      );
      if (!candidate.existsSync()) {
        return candidate;
      }
    }
    return file;
  }

  /// 创建压缩包。
  static Uint8List createArchive({
    required List<(String, List<int>)> files,
    required ArchiveFormat format,
  }) {
    final Archive archive = Archive();
    for (final (String name, List<int> data) in files) {
      final String? safe = safeRelativePath(name);
      if (safe == null) {
        throw FormatException('文件名不安全：$name');
      }
      archive.addFile(ArchiveFile.bytes(safe, data));
    }
    switch (format) {
      case ArchiveFormat.zip:
        return Uint8List.fromList(ZipEncoder().encode(archive));
      case ArchiveFormat.tar:
        return Uint8List.fromList(TarEncoder().encode(archive));
      case ArchiveFormat.gzip:
        final List<int> tar = TarEncoder().encode(archive);
        return Uint8List.fromList(GZipEncoder().encode(tar));
      default:
        throw UnsupportedError('暂不支持创建该格式');
    }
  }
}
