import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ReplaceFileWNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _ReplaceFileWDart = int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

abstract final class AtomicFile {
  static Future<void> commit(File temporary, File destination) async {
    if (!await destination.exists()) {
      await temporary.rename(destination.path);
      return;
    }
    if (!Platform.isWindows) {
      await destination.delete();
      await temporary.rename(destination.path);
      return;
    }
    final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');
    final _ReplaceFileWDart replaceFile = kernel
        .lookupFunction<_ReplaceFileWNative, _ReplaceFileWDart>('ReplaceFileW');
    final _GetLastErrorDart getLastError = kernel
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
    final Pointer<Utf16> destinationPath = destination.path.toNativeUtf16();
    final Pointer<Utf16> temporaryPath = temporary.path.toNativeUtf16();
    try {
      final int replaced = replaceFile(
        destinationPath,
        temporaryPath,
        nullptr,
        0,
        nullptr,
        nullptr,
      );
      if (replaced == 0) {
        throw FileSystemException(
          'ReplaceFileW 原子替换失败（Win32 ${getLastError()}）',
          destination.path,
        );
      }
    } finally {
      malloc.free(destinationPath);
      malloc.free(temporaryPath);
    }
  }
}
