import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _FileTime extends Struct {
  @Uint32()
  external int low;

  @Uint32()
  external int high;
}

final class _ByHandleFileInformation extends Struct {
  @Uint32()
  external int attributes;

  external _FileTime creationTime;
  external _FileTime accessTime;
  external _FileTime writeTime;

  @Uint32()
  external int volumeSerialNumber;

  @Uint32()
  external int fileSizeHigh;

  @Uint32()
  external int fileSizeLow;

  @Uint32()
  external int numberOfLinks;

  @Uint32()
  external int fileIndexHigh;

  @Uint32()
  external int fileIndexLow;
}

typedef _CreateFileWNative = Pointer<Void> Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  Pointer<Void>,
);
typedef _CreateFileWDart = Pointer<Void> Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
);
typedef _GetFileInformationNative = Int32 Function(
  Pointer<Void>,
  Pointer<_ByHandleFileInformation>,
);
typedef _GetFileInformationDart = int Function(
  Pointer<Void>,
  Pointer<_ByHandleFileInformation>,
);
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);

// Resolving kernel32 exports for every scanned file made a 45k-file cleanup
// inventory take minutes. Resolve once per worker isolate instead.
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final _CreateFileWDart _createFile = _kernel32
    .lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW');
final _GetFileInformationDart _getFileInformation = _kernel32
    .lookupFunction<_GetFileInformationNative, _GetFileInformationDart>(
      'GetFileInformationByHandle',
    );
final _CloseHandleDart _closeHandle = _kernel32
    .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

class CleanupFileIdentity {
  const CleanupFileIdentity({
    required this.volumeSerialNumber,
    required this.fileIndex,
  });

  final int volumeSerialNumber;
  final int fileIndex;

  static CleanupFileIdentity? read(String path) {
    if (!Platform.isWindows) return null;
    final Pointer<Utf16> nativePath = path.toNativeUtf16();
    const int shareReadWriteDelete = 0x00000001 | 0x00000002 | 0x00000004;
    const int openExisting = 3;
    const int backupSemantics = 0x02000000;
    final Pointer<Void> handle = _createFile(
      nativePath,
      0,
      shareReadWriteDelete,
      nullptr,
      openExisting,
      backupSemantics,
      nullptr,
    );
    malloc.free(nativePath);
    if (handle == Pointer<Void>.fromAddress(-1)) return null;
    final Pointer<_ByHandleFileInformation> information =
        calloc<_ByHandleFileInformation>();
    try {
      if (_getFileInformation(handle, information) == 0) return null;
      final _ByHandleFileInformation value = information.ref;
      return CleanupFileIdentity(
        volumeSerialNumber: value.volumeSerialNumber,
        fileIndex: (value.fileIndexHigh << 32) | value.fileIndexLow,
      );
    } finally {
      _closeHandle(handle);
      calloc.free(information);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CleanupFileIdentity &&
      other.volumeSerialNumber == volumeSerialNumber &&
      other.fileIndex == fileIndex;

  @override
  int get hashCode => Object.hash(volumeSerialNumber, fileIndex);
}
