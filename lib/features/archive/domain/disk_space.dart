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

abstract final class DiskSpace {
  static int? availableBytes(String path) {
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
      return available.value;
    } finally {
      malloc.free(nativePath);
      calloc.free(available);
      calloc.free(total);
      calloc.free(free);
    }
  }
}
