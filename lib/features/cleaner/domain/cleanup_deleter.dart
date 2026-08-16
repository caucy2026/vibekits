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
typedef _GetFileAttributesWNative = Uint32 Function(Pointer<Utf16> path);
typedef _GetFileAttributesWDart = int Function(Pointer<Utf16> path);
typedef _SetFileAttributesWNative = Int32 Function(
  Pointer<Utf16> path,
  Uint32 attributes,
);
typedef _SetFileAttributesWDart = int Function(
  Pointer<Utf16> path,
  int attributes,
);

class _RecycleResult {
  const _RecycleResult({required this.code, required this.aborted});

  final int code;
  final bool aborted;

  bool get succeeded => code == 0 && !aborted;
}

/// 删除器：回收站优先，永久删除需单独确认（docs/00 §4.2，CLN-006）。
abstract final class CleanupDeleter {
  static const int _foDelete = 3;
  static const int _fofAllowUndo = 0x0040;
  static const int _fofNoConfirmation = 0x0010;
  static const int _fofSilent = 0x0004;
  static const int _fofNoErrorUi = 0x0400;

  /// 将文件移入回收站；返回 true 表示成功。
  static bool sendToRecycleBin(List<String> paths) =>
      _sendToRecycleBin(paths).succeeded;

  static _RecycleResult _sendToRecycleBin(List<String> paths) {
    if (paths.isEmpty) return const _RecycleResult(code: 0, aborted: false);
    if (Platform.isMacOS) return _sendToMacTrash(paths);
    if (!Platform.isWindows) {
      return const _RecycleResult(code: -1, aborted: false);
    }
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
      return _RecycleResult(
        code: result,
        aborted: struct.ref.fAnyOperationsAborted != 0,
      );
    } finally {
      malloc.free(pFrom);
      calloc.free(struct);
    }
  }

  static _RecycleResult _sendToMacTrash(List<String> paths) {
    final String? home = Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      return const _RecycleResult(code: -2, aborted: false);
    }
    final Directory trash = Directory('$home${Platform.pathSeparator}.Trash');
    try {
      if (!trash.existsSync()) trash.createSync(recursive: true);
      for (final String path in paths) {
        final FileSystemEntityType type = FileSystemEntity.typeSync(
          path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory) {
          return const _RecycleResult(code: -3, aborted: false);
        }
        final String name = path
            .replaceAll('\\', '/')
            .split('/')
            .where((String part) => part.isNotEmpty)
            .last;
        String destination = '${trash.path}${Platform.pathSeparator}$name';
        int suffix = 1;
        while (FileSystemEntity.typeSync(destination, followLinks: false) !=
            FileSystemEntityType.notFound) {
          destination =
              '${trash.path}${Platform.pathSeparator}$name.vibekits-$suffix';
          suffix++;
        }
        if (type == FileSystemEntityType.directory) {
          Directory(path).renameSync(destination);
        } else {
          File(path).renameSync(destination);
        }
      }
      return const _RecycleResult(code: 0, aborted: false);
    } on FileSystemException {
      return const _RecycleResult(code: -4, aborted: false);
    }
  }

  /// 永久删除单个路径（不进入回收站）。
  static bool deletePermanently(String path) {
    try {
      _clearReadOnlyTree(path);
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        File(path).deleteSync();
      }
      return FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  static Future<CleanupDeleteResult> deleteCandidates(
    List<CleanupCandidate> candidates, {
    CleanupCancellationToken? cancellationToken,
    void Function(CleanupDeleteProgress progress)? onProgress,
    bool Function(String path)? recycle,
    bool permanentFallback = false,
  }) async {
    final CleanupCancellationToken token =
        cancellationToken ?? CleanupCancellationToken();
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
          final _RecycleResult? shellResult = recycle == null
              ? _sendToRecycleBin(<String>[candidate.path])
              : null;
          final bool accepted =
              shellResult?.succeeded ?? recycle!(candidate.path);
          bool removed = await _waitUntilRemoved(candidate.path);
          if (accepted && removed) {
            releasedBytes += candidate.size;
            items.add(
              CleanupItemResult(
                candidate: candidate,
                status: CleanupItemStatus.succeeded,
                reason: '已移入回收站',
              ),
            );
          } else if (permanentFallback &&
              candidate.allowsPermanentFallback &&
              deletePermanently(candidate.path)) {
            removed = await _waitUntilRemoved(candidate.path);
            if (removed) {
              releasedBytes += candidate.size;
              items.add(
                CleanupItemResult(
                  candidate: candidate,
                  status: CleanupItemStatus.succeeded,
                  reason: '回收站操作失败后，已永久删除可再生成缓存',
                ),
              );
            }
          } else {
            final String shellReason = shellResult == null
                ? (accepted ? '测试删除器未移除项目' : '删除器拒绝操作')
                : shellResult.aborted
                ? '用户或系统中止了回收站操作'
                : shellResult.code == 0
                ? '系统废纸篓未移除项目'
                : '系统废纸篓错误 ${shellResult.code}';
            items.add(
              CleanupItemResult(
                candidate: candidate,
                status: CleanupItemStatus.failed,
                reason: '$shellReason；文件可能正被程序占用或权限不足，请关闭来源应用后重试',
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
      // Leave short I/O gaps so cleanup does not monopolize a busy disk.
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }

    return CleanupDeleteResult(
      items: items,
      cancelled: token.isCancelled,
      releasedBytes: releasedBytes,
    );
  }

  static Future<bool> _waitUntilRemoved(String path) async {
    for (int attempt = 0; attempt < 5; attempt++) {
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  static void _clearReadOnlyTree(String path) {
    if (!Platform.isWindows) return;
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.directory) {
      try {
        for (final FileSystemEntity entity in Directory(
          path,
        ).listSync(recursive: true, followLinks: false)) {
          _clearReadOnly(entity.path);
        }
      } on FileSystemException {
        // 继续尝试清理已能访问的项目，最终删除结果会给出失败状态。
      }
    }
    _clearReadOnly(path);
  }

  static void _clearReadOnly(String path) {
    final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');
    final _GetFileAttributesWDart getAttributes = kernel
        .lookupFunction<_GetFileAttributesWNative, _GetFileAttributesWDart>(
          'GetFileAttributesW',
        );
    final _SetFileAttributesWDart setAttributes = kernel
        .lookupFunction<_SetFileAttributesWNative, _SetFileAttributesWDart>(
          'SetFileAttributesW',
        );
    final Pointer<Utf16> nativePath = path.toNativeUtf16();
    try {
      final int attributes = getAttributes(nativePath);
      if (attributes != 0xFFFFFFFF && attributes & 0x1 != 0) {
        setAttributes(nativePath, attributes & ~0x1);
      }
    } finally {
      malloc.free(nativePath);
    }
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
