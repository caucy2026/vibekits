import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'cleanup_scanner.dart';
import 'cleanup_task.dart';
import 'cleanup_file_identity.dart';

enum CleanupItemStatus { succeeded, skipped, failed }

class CleanupItemResult {
  const CleanupItemResult({
    required this.candidate,
    required this.status,
    required this.reason,
  });

  final CleanupCandidate candidate;
  final CleanupItemStatus status;
  final String reason;
}

class CleanupDeleteProgress {
  const CleanupDeleteProgress({required this.completed, required this.total});

  final int completed;
  final int total;
}

class CleanupDeleteResult {
  const CleanupDeleteResult({
    required this.items,
    required this.cancelled,
    required this.releasedBytes,
  });

  final List<CleanupItemResult> items;
  final bool cancelled;
  final int releasedBytes;

  int get succeeded => items
      .where(
        (CleanupItemResult item) => item.status == CleanupItemStatus.succeeded,
      )
      .length;
  int get skipped => items
      .where(
        (CleanupItemResult item) => item.status == CleanupItemStatus.skipped,
      )
      .length;
  int get failed => items
      .where(
        (CleanupItemResult item) => item.status == CleanupItemStatus.failed,
      )
      .length;
}

/// SHFILEOPSTRUCTW 结构（仅删除所需字段）。
final class _ShFileOpStruct extends Struct {
  external Pointer<Void> hwnd;

  @Uint32()
  external int wFunc;

  external Pointer<Utf16> pFrom;

  external Pointer<Utf16> pTo;

  @Uint16()
  external int fFlags;

  @Int32()
  external int fAnyOperationsAborted;

  external Pointer<Void> hNameMappings;

  external Pointer<Utf16> lpszProgressTitle;
}

typedef _ShFileOperationWNative = Int32 Function(Pointer<_ShFileOpStruct>);
typedef _ShFileOperationWDart = int Function(Pointer<_ShFileOpStruct>);

/// 删除器：回收站优先，永久删除需单独确认（docs/00 §4.2，CLN-006）。
abstract final class CleanupDeleter {
  static const int _foDelete = 3;
  static const int _fofAllowUndo = 0x0040;
  static const int _fofNoConfirmation = 0x0010;
  static const int _fofSilent = 0x0004;
  static const int _fofNoErrorUi = 0x0400;

  /// 将文件移入回收站；返回 true 表示成功。
  static bool sendToRecycleBin(List<String> paths) {
    if (paths.isEmpty) return true;
    final DynamicLibrary lib = DynamicLibrary.open('shell32.dll');
    final _ShFileOperationWDart fn = lib
        .lookupFunction<_ShFileOperationWNative, _ShFileOperationWDart>(
          'SHFileOperationW',
        );

    // pFrom 为双空终止的宽字符串序列。
    final String joined = '${paths.map((String p) => '$p\u0000').join()}\u0000';
    final Pointer<Utf16> pFrom = joined.toNativeUtf16();
    final Pointer<_ShFileOpStruct> struct = calloc<_ShFileOpStruct>();
    try {
      struct.ref.hwnd = nullptr;
      struct.ref.wFunc = _foDelete;
      struct.ref.pFrom = pFrom;
      struct.ref.pTo = nullptr;
      struct.ref.fFlags =
          _fofAllowUndo | _fofNoConfirmation | _fofSilent | _fofNoErrorUi;
      struct.ref.fAnyOperationsAborted = 0;
      struct.ref.hNameMappings = nullptr;
      struct.ref.lpszProgressTitle = nullptr;
      final int result = fn(struct);
      return result == 0;
    } finally {
      malloc.free(pFrom);
      calloc.free(struct);
    }
  }

  /// 永久删除单个路径（不进入回收站）。
  static bool deletePermanently(String path) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(path);
    try {
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else {
        File(path).deleteSync();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<CleanupDeleteResult> deleteCandidates(
    List<CleanupCandidate> candidates, {
    CleanupCancellationToken? cancellationToken,
    void Function(CleanupDeleteProgress progress)? onProgress,
    bool Function(String path)? recycle,
  }) async {
    final CleanupCancellationToken token =
        cancellationToken ?? CleanupCancellationToken();
    final bool Function(String path) recyclePath =
        recycle ?? (String path) => sendToRecycleBin(<String>[path]);
    final List<CleanupItemResult> items = <CleanupItemResult>[];
    int releasedBytes = 0;

    for (final CleanupCandidate candidate in candidates) {
      if (token.isCancelled) break;
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        candidate.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        items.add(
          CleanupItemResult(
            candidate: candidate,
            status: CleanupItemStatus.skipped,
            reason: '扫描后已不存在',
          ),
        );
      } else if (!_unchanged(candidate, type)) {
        items.add(
          CleanupItemResult(
            candidate: candidate,
            status: CleanupItemStatus.skipped,
            reason: '扫描后文件已变化',
          ),
        );
      } else {
        try {
          final bool accepted = recyclePath(candidate.path);
          final bool removed =
              FileSystemEntity.typeSync(candidate.path, followLinks: false) ==
              FileSystemEntityType.notFound;
          if (accepted && removed) {
            releasedBytes += candidate.size;
            items.add(
              CleanupItemResult(
                candidate: candidate,
                status: CleanupItemStatus.succeeded,
                reason: '已移入回收站',
              ),
            );
          } else {
            items.add(
              CleanupItemResult(
                candidate: candidate,
                status: CleanupItemStatus.failed,
                reason: accepted ? 'Shell 未移除项目' : 'Shell 拒绝操作',
              ),
            );
          }
        } catch (error) {
          items.add(
            CleanupItemResult(
              candidate: candidate,
              status: CleanupItemStatus.failed,
              reason: '操作异常：${error.runtimeType}',
            ),
          );
        }
      }
      onProgress?.call(
        CleanupDeleteProgress(
          completed: items.length,
          total: candidates.length,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    return CleanupDeleteResult(
      items: items,
      cancelled: token.isCancelled,
      releasedBytes: releasedBytes,
    );
  }

  static bool _unchanged(
    CleanupCandidate candidate,
    FileSystemEntityType type,
  ) {
    final CleanupFileIdentity? expectedIdentity = candidate.identity;
    if (expectedIdentity != null &&
        CleanupFileIdentity.read(candidate.path) != expectedIdentity) {
      return false;
    }
    if (type == FileSystemEntityType.file) {
      try {
        final File file = File(candidate.path);
        return file.lengthSync() == candidate.size &&
            (candidate.modified == null ||
                file.lastModifiedSync() == candidate.modified);
      } on FileSystemException {
        return false;
      }
    }
    if (type == FileSystemEntityType.directory) {
      try {
        return candidate.size == 0 &&
            Directory(candidate.path).listSync().isEmpty;
      } on FileSystemException {
        return false;
      }
    }
    return false;
  }
}
