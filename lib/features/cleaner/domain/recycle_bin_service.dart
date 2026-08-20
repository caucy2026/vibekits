import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _ShellQueryRecycleBinInfo extends Struct {
  @Uint32()
  external int size;

  @Int64()
  external int bytes;

  @Int64()
  external int items;
}

typedef _QueryNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<_ShellQueryRecycleBinInfo>,
);
typedef _QueryDart = int Function(
  Pointer<Utf16>,
  Pointer<_ShellQueryRecycleBinInfo>,
);
typedef _EmptyNative = Int32 Function(Pointer<Void>, Pointer<Utf16>, Uint32);
typedef _EmptyDart = int Function(Pointer<Void>, Pointer<Utf16>, int);

class RecycleBinSnapshot {
  const RecycleBinSnapshot({required this.bytes, required this.items});

  final int bytes;
  final int items;
}

abstract final class RecycleBinService {
  static RecycleBinSnapshot? query(String rootPath) {
    if (!Platform.isWindows) return null;
    final DynamicLibrary shell = DynamicLibrary.open('shell32.dll');
    final _QueryDart query = shell.lookupFunction<_QueryNative, _QueryDart>(
      'SHQueryRecycleBinW',
    );
    final Pointer<Utf16> root = rootPath.toNativeUtf16();
    final Pointer<_ShellQueryRecycleBinInfo> info =
        calloc<_ShellQueryRecycleBinInfo>();
    info.ref.size = sizeOf<_ShellQueryRecycleBinInfo>();
    try {
      if (query(root, info) != 0) return null;
      return RecycleBinSnapshot(bytes: info.ref.bytes, items: info.ref.items);
    } finally {
      malloc.free(root);
      calloc.free(info);
    }
  }

  static bool empty(String rootPath) {
    if (!Platform.isWindows) return false;
    final DynamicLibrary shell = DynamicLibrary.open('shell32.dll');
    final _EmptyDart empty = shell.lookupFunction<_EmptyNative, _EmptyDart>(
      'SHEmptyRecycleBinW',
    );
    final Pointer<Utf16> root = rootPath.toNativeUtf16();
    try {
      const int noConfirmation = 0x00000001;
      const int noProgressUi = 0x00000002;
      const int noSound = 0x00000004;
      return empty(nullptr, root, noConfirmation | noProgressUi | noSound) == 0;
    } finally {
      malloc.free(root);
    }
  }
}
