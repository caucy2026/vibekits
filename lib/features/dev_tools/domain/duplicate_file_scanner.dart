import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../../cleaner/domain/cleanup_file_identity.dart';
import '../../cleaner/domain/cleanup_task.dart';

enum DuplicateScanPhase { enumerating, hashing }

class DuplicateFileEntry {
  const DuplicateFileEntry({
    required this.path,
    required this.size,
    required this.modified,
    required this.sha256,
    this.identity,
  });

  final String path;
  final int size;
  final DateTime modified;
  final String sha256;
  final CleanupFileIdentity? identity;
}

class DuplicateFileGroup {
  const DuplicateFileGroup({
    required this.sha256,
    required this.size,
    required this.files,
  });

  final String sha256;
  final int size;
  final List<DuplicateFileEntry> files;

  int get reclaimableBytes => size * (files.length - 1);
  DuplicateFileEntry get suggestedKeep => files.first;
}

class DuplicateScanProgress {
  const DuplicateScanProgress({
    required this.phase,
    required this.currentPath,
    required this.visitedFiles,
    required this.hashCompleted,
    required this.hashTotal,
    required this.hashedBytes,
    required this.totalHashBytes,
  });

  final DuplicateScanPhase phase;
  final String currentPath;
  final int visitedFiles;
  final int hashCompleted;
  final int hashTotal;
  final int hashedBytes;
  final int totalHashBytes;
}

class DuplicateScanResult {
  const DuplicateScanResult({
    required this.groups,
    required this.cancelled,
    required this.visitedFiles,
    required this.hashedFiles,
    required this.unreadablePaths,
  });

  final List<DuplicateFileGroup> groups;
  final bool cancelled;
  final int visitedFiles;
  final int hashedFiles;
  final int unreadablePaths;

  int get duplicateFiles => groups.fold<int>(
    0,
    (int total, DuplicateFileGroup group) => total + group.files.length - 1,
  );
  int get reclaimableBytes => groups.fold<int>(
    0,
    (int total, DuplicateFileGroup group) => total + group.reclaimableBytes,
  );
}

abstract final class DuplicateFileScanner {
  static Future<DuplicateScanResult> scan(
    String root, {
    bool recursive = true,
    int minimumSize = 1024 * 1024,
    CleanupCancellationToken? cancellationToken,
    void Function(DuplicateScanProgress progress)? onProgress,
  }) async {
    final CleanupCancellationToken token =
        cancellationToken ?? CleanupCancellationToken();
    final Directory rootDirectory = Directory(root.trim());
    if (!rootDirectory.existsSync()) {
      throw const FileSystemException('文件夹不存在');
    }

    final Map<int, List<_ScannedFile>> bySize = <int, List<_ScannedFile>>{};
    final List<Directory> pending = <Directory>[rootDirectory];
    int visitedFiles = 0;
    int unreadablePaths = 0;

    while (pending.isNotEmpty && !token.isCancelled) {
      final Directory directory = pending.removeLast();
      try {
        await for (final FileSystemEntity entity in directory.list(
          followLinks: false,
        )) {
          if (token.isCancelled) break;
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.directory) {
            if (recursive && !_isSystemMetadataDirectory(entity.path)) {
              pending.add(Directory(entity.path));
            }
            continue;
          }
          if (type != FileSystemEntityType.file) continue;
          visitedFiles++;
          try {
            final FileStat stat = File(entity.path).statSync();
            if (stat.size >= minimumSize) {
              bySize
                  .putIfAbsent(stat.size, () => <_ScannedFile>[])
                  .add(
                    _ScannedFile(
                      path: entity.path,
                      size: stat.size,
                      modified: stat.modified,
                    ),
                  );
            }
          } on FileSystemException {
            unreadablePaths++;
          }
          onProgress?.call(
            DuplicateScanProgress(
              phase: DuplicateScanPhase.enumerating,
              currentPath: entity.path,
              visitedFiles: visitedFiles,
              hashCompleted: 0,
              hashTotal: 0,
              hashedBytes: 0,
              totalHashBytes: 0,
            ),
          );
          if (visitedFiles % 50 == 0) await Future<void>.delayed(Duration.zero);
        }
      } on FileSystemException {
        unreadablePaths++;
      }
    }

    final List<_ScannedFile> hashCandidates = <_ScannedFile>[];
    for (final List<_ScannedFile> sameSize in bySize.values) {
      if (sameSize.length < 2) continue;
      // 相同物理文件的硬链接只保留一个，避免把零收益操作当作重复文件。
      final Set<CleanupFileIdentity> identities = <CleanupFileIdentity>{};
      for (final _ScannedFile file in sameSize) {
        file.identity = CleanupFileIdentity.read(file.path);
        if (file.identity != null && !identities.add(file.identity!)) continue;
        hashCandidates.add(file);
      }
    }
    final int totalHashBytes = hashCandidates.fold<int>(
      0,
      (int total, _ScannedFile file) => total + file.size,
    );
    final Map<String, List<DuplicateFileEntry>> byHash =
        <String, List<DuplicateFileEntry>>{};
    int hashCompleted = 0;
    int hashedBytes = 0;

    for (final _ScannedFile candidate in hashCandidates) {
      if (token.isCancelled) break;
      try {
        final String? digest = await _sha256(
          File(candidate.path),
          token,
          onBytes: (int bytes) {
            onProgress?.call(
              DuplicateScanProgress(
                phase: DuplicateScanPhase.hashing,
                currentPath: candidate.path,
                visitedFiles: visitedFiles,
                hashCompleted: hashCompleted,
                hashTotal: hashCandidates.length,
                hashedBytes: hashedBytes + bytes,
                totalHashBytes: totalHashBytes,
              ),
            );
          },
        );
        if (digest == null) break;
        final FileStat after = File(candidate.path).statSync();
        if (after.size != candidate.size ||
            after.modified != candidate.modified) {
          unreadablePaths++;
          continue;
        }
        final DuplicateFileEntry entry = DuplicateFileEntry(
          path: candidate.path,
          size: candidate.size,
          modified: candidate.modified,
          sha256: digest,
          identity: candidate.identity,
        );
        byHash
            .putIfAbsent(
              '${candidate.size}:$digest',
              () => <DuplicateFileEntry>[],
            )
            .add(entry);
      } on FileSystemException {
        unreadablePaths++;
      }
      hashCompleted++;
      hashedBytes += candidate.size;
      await Future<void>.delayed(Duration.zero);
    }

    final List<DuplicateFileGroup> groups = <DuplicateFileGroup>[];
    for (final List<DuplicateFileEntry> files in byHash.values) {
      if (files.length < 2) continue;
      files.sort(
        (DuplicateFileEntry left, DuplicateFileEntry right) =>
            right.modified.compareTo(left.modified),
      );
      groups.add(
        DuplicateFileGroup(
          sha256: files.first.sha256,
          size: files.first.size,
          files: List<DuplicateFileEntry>.unmodifiable(files),
        ),
      );
    }
    groups.sort(
      (DuplicateFileGroup left, DuplicateFileGroup right) =>
          right.reclaimableBytes.compareTo(left.reclaimableBytes),
    );

    return DuplicateScanResult(
      groups: List<DuplicateFileGroup>.unmodifiable(groups),
      cancelled: token.isCancelled,
      visitedFiles: visitedFiles,
      hashedFiles: hashCompleted,
      unreadablePaths: unreadablePaths,
    );
  }

  static Future<String?> _sha256(
    File file,
    CleanupCancellationToken token, {
    required void Function(int bytes) onBytes,
  }) async {
    crypto.Digest? digest;
    int processed = 0;
    final ByteConversionSink sink = crypto.sha256.startChunkedConversion(
      _DigestSink((crypto.Digest value) => digest = value),
    );
    await for (final List<int> chunk in file.openRead()) {
      if (token.isCancelled) break;
      sink.add(chunk);
      processed += chunk.length;
      onBytes(processed);
    }
    sink.close();
    return token.isCancelled ? null : digest?.toString();
  }

  static bool _isSystemMetadataDirectory(String path) {
    final String name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .toLowerCase();
    return name == r'$recycle.bin' || name == 'system volume information';
  }
}

class _ScannedFile {
  _ScannedFile({
    required this.path,
    required this.size,
    required this.modified,
  });

  final String path;
  final int size;
  final DateTime modified;
  CleanupFileIdentity? identity;
}

class _DigestSink implements Sink<crypto.Digest> {
  _DigestSink(this.onDigest);

  final void Function(crypto.Digest digest) onDigest;

  @override
  void add(crypto.Digest data) => onDigest(data);

  @override
  void close() {}
}
