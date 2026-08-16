import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetDiskFreeSpaceExWNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _GetDiskFreeSpaceExWDart = int Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);

class DiskSpaceSnapshot {
  const DiskSpaceSnapshot({
    required this.path,
    required this.availableBytes,
    required this.totalBytes,
    required this.freeBytes,
  });

  final String path;
  final int availableBytes;
  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
}

abstract final class DiskSpace {
  static DiskSpaceSnapshot? snapshot(String path) {
    if (!Platform.isWindows) return null;
    final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');
    final _GetDiskFreeSpaceExWDart getDiskFreeSpace = kernel
        .lookupFunction<_GetDiskFreeSpaceExWNative, _GetDiskFreeSpaceExWDart>(
          'GetDiskFreeSpaceExW',
        );
    final Pointer<Utf16> nativePath = path.toNativeUtf16();
    final Pointer<Uint64> available = calloc<Uint64>();
    final Pointer<Uint64> total = calloc<Uint64>();
    final Pointer<Uint64> free = calloc<Uint64>();
    try {
      if (getDiskFreeSpace(nativePath, available, total, free) == 0) {
        return null;
      }
      return DiskSpaceSnapshot(
        path: path,
        availableBytes: available.value,
        totalBytes: total.value,
        freeBytes: free.value,
      );
    } finally {
      malloc.free(nativePath);
      calloc.free(available);
      calloc.free(total);
      calloc.free(free);
    }
  }

  static int? availableBytes(String path) => snapshot(path)?.availableBytes;
}
